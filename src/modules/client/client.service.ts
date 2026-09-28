import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
import { randomInt, randomUUID } from 'node:crypto';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { redis } from '../../config/redis.js';
import { ValidationError, NotFoundError, ForbiddenError, ConflictError, UnauthorizedError } from '../../shared/utils/errors.js';
import { WebSocketService } from '../../shared/services/websocket.js';
import { AdminService } from '../admin/admin.service.js';
import { sendPushNotification } from '../../config/fcm.js';
import {
  RAZORPAY_CURRENCY,
  isMockPaymentsAllowed,
  isMockOrderId,
  isMockPaymentId,
  paiseToRupees,
  toPaise,
  verifyRazorpayPaymentSignature,
  verifyRazorpayWebhookSignature,
} from '../../shared/utils/razorpay.js';
import {
  SAFE_PARTNER_PUBLIC_SELECT,
  SAFE_USER_PUBLIC_SELECT,
  resolveWebhookTransition,
  sanitizeBookingForResponse,
  toBookingEvent,
  toOwnerPartner,
  toPublicUser,
  toSelfUser,
} from '../../shared/utils/bookingPrivacy.js';
import {
  BOOKING_STATUS,
  assertBookingTransition,
  canRegisterTournament,
  computeCouponDiscount,
  computeRefundQuote,
  ensureReviewEligible,
} from '../../shared/utils/bookingLifecycle.js';
import { notifyPartner, notifyUser } from '../../shared/services/notifications.js';
import { releaseBookingOnFailedPayment } from '../../shared/services/paymentFailure.js';
import { requestBookingRefund } from '../../shared/services/refunds.js';
import { claimCouponUsage, recordCouponRedemption, rollbackCouponForBooking } from '../../shared/services/coupons.js';
import { createSession, refreshSession, revokeAllSessions, revokeSession } from '../../shared/utils/sessions.js';
import { normalizeAuthRole, verifyGoogleIdToken } from '../../shared/utils/googleAuth.js';

const OTP_RESEND_COOLDOWN_KEY = (phone: string) => `otp:cooldown:${phone}`;
const BOOKING_PAYMENT_GUARD_KEY = (paymentId: string) => `processed_booking_payment:${paymentId}`;
const WEBHOOK_EVENT_GUARD_KEY = (eventId: string) => `processed_webhook_event:${eventId}`;

/** Internal markers for the verify-payment confirm race (never cross API). */
class ConfirmRaceError extends Error {}
class ConfirmExpiredError extends Error {}

/** Razorpay credentials: explicit env first, Redis system_settings fallback. */
async function resolveRazorpayKeys(): Promise<{ keyId: string; keySecret: string }> {
  if (env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET) {
    return { keyId: env.RAZORPAY_KEY_ID, keySecret: env.RAZORPAY_KEY_SECRET };
  }
  const settings = await AdminService.getSettings();
  return {
    keyId: settings.razorpayKeyId || '',
    keySecret: settings.razorpayKeySecret || '',
  };
}

function razorpayBasicAuth(keyId: string, keySecret: string): string {
  return Buffer.from(`${keyId}:${keySecret}`).toString('base64');
}

async function fetchRazorpayPayment(paymentId: string, keyId: string, keySecret: string): Promise<any> {
  const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Basic ${razorpayBasicAuth(keyId, keySecret)}` },
  });
  return response.json();
}

export class ClientService {
  // 1. Auth Service
  public static async requestOtp(phoneNumber: string, password?: string, isSignUp?: boolean, role: string = 'partner') {
    const settings = await AdminService.getSettings();

    if (!phoneNumber || typeof phoneNumber !== 'string') {
      throw new ValidationError("Phone number is required");
    }
    // Resend cooldown: one OTP per phone per cooldown window.
    const cooldown = await redis.get(OTP_RESEND_COOLDOWN_KEY(phoneNumber));
    if (cooldown) {
      throw new ValidationError("An OTP was sent recently. Please wait before requesting another.");
    }

    if (role === 'partner') {
      // 1. Check if partner exists
      const partner = await prisma.partner.findFirst({
        where: {
          OR: [
            { email: phoneNumber },
            { phone_number: phoneNumber }
          ]
        }
      });

      if (partner) {
        if (isSignUp) {
          throw new ValidationError("Account already exists. Please log in.");
        }
        if (!password) {
          throw new ValidationError("Password is required to log in");
        }
        const partnerObj = partner as any;
        if (partnerObj.password_hash) {
          const isPasswordCorrect = await bcrypt.compare(password, partnerObj.password_hash);
          if (!isPasswordCorrect) {
            throw new ValidationError("Invalid email/phone or password");
          }
        }
      } else {
        // Sign up flow
        if (!isSignUp) {
          throw new ValidationError("Account does not exist. Please sign up.");
        }
        if (!password) {
          throw new ValidationError("Password is required to register");
        }
        
        const newPartnerData: any = {
          phone_number: phoneNumber,
          email: phoneNumber.includes('@') ? phoneNumber : null,
          password_hash: await bcrypt.hash(password, 10),
          kyc_status: 'unverified', // Start as unverified by default
          total_earnings: 0.0
        };
        
        await prisma.partner.create({
          data: newPartnerData
        });
      }
    } else {
      // 1. Check if user exists
      const user = await prisma.user.findFirst({
        where: {
          OR: [
            { email: phoneNumber },
            { phone_number: phoneNumber }
          ]
        }
      });

      if (user) {
        if (isSignUp) {
          throw new ValidationError("Account already exists. Please log in.");
        }
        if (!password) {
          throw new ValidationError("Password is required to log in");
        }
        const userObj = user as any;
        if (userObj.password_hash) {
          const isPasswordCorrect = await bcrypt.compare(password, userObj.password_hash);
          if (!isPasswordCorrect) {
            throw new ValidationError("Invalid email/phone or password");
          }
        }
      } else {
        // Sign up flow
        if (!isSignUp) {
          throw new ValidationError("Account does not exist. Please sign up.");
        }
        if (!password) {
          throw new ValidationError("Password is required to register");
        }
        
        const newUserData: any = {
          phone_number: phoneNumber,
          email: phoneNumber.includes('@') ? phoneNumber : null,
          password_hash: await bcrypt.hash(password, 10),
          status: 'Active',
          total_bookings: 0,
          total_spend: 0.0
        };
        
        await prisma.user.create({
          data: newUserData
        });
      }
    }

    const code = randomInt(100000, 1000000).toString();
    const hash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await prisma.otpLog.create({
      data: {
        phone_number: phoneNumber,
        otp_hash: hash,
        expires_at: expiresAt,
        attempt_count: 0
      }
    });

    // Resend cooldown marker (route-level rate limiting also applies).
    await redis.set(OTP_RESEND_COOLDOWN_KEY(phoneNumber), '1', {
      EX: env.OTP_RESEND_COOLDOWN_SECONDS,
    });

    // The real OTP is NEVER returned or logged in production. Dev echoes
    // require OTP_DEV_MODE=true and are refused when NODE_ENV=production.
    const devOtpEcho =
      process.env.OTP_DEV_MODE === 'true' && process.env.NODE_ENV !== 'production'
        ? { otp: code }
        : {};

    if (settings.useSmtpForOtp && settings.smtpHost) {
      let email = phoneNumber;
      if (!phoneNumber.includes('@')) {
        const user = await prisma.user.findUnique({ where: { phone_number: phoneNumber } });
        if (user && user.email) {
          email = user.email;
        } else {
          throw new ValidationError("No registered email found for this phone number. Please log in with your email address directly.");
        }
      }

      try {
        const transporter = nodemailer.createTransport({
          host: settings.smtpHost,
          port: Number(settings.smtpPort),
          secure: !!settings.smtpSecure,
          auth: settings.smtpUser ? {
            user: settings.smtpUser,
            pass: settings.smtpPass
          } : undefined
        });

        await transporter.sendMail({
          from: settings.smtpFrom || settings.smtpUser || 'noreply@athletepov.com',
          to: email,
          subject: `${settings.platformName || "Athlete's POV"} Login OTP`,
          text: `Your OTP for logging in to ${settings.platformName || "Athlete's POV"} is: ${code}. It is valid for 10 minutes.`,
          html: `<div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 5px;">
            <h2 style="color: #10B981;">${settings.platformName || "Athlete's POV"}</h2>
            <p>Your One-Time Password (OTP) for login is:</p>
            <div style="font-size: 24px; font-weight: bold; color: #333; letter-spacing: 2px; margin: 20px 0; padding: 10px; background-color: #f9f9f9; border-radius: 4px; display: inline-block;">
              ${code}
            </div>
            <p>This OTP is valid for 10 minutes. Please do not share this code with anyone.</p>
          </div>`
        });

        return { message: `OTP sent to email: ${email}`, ...devOtpEcho };
      } catch (mailErr: any) {
        // Never leak the OTP in error/fallback responses.
        throw new ValidationError("Failed to send OTP. Please try again later.");
      }
    }

    if (process.env.NODE_ENV === 'production') {
      return { message: `OTP sent to ${phoneNumber}` };
    }
    return { message: `Simulated SMS: OTP for ${phoneNumber} issued`, ...devOtpEcho };
  }

  /**
   * Google Sign-In (P0): the mobile app MUST send the Google ID token.
   * Identity is derived ONLY from the verified token — never from
   * client-supplied email/name — and the role can only be user|partner.
   */
  public static async googleLogin(idToken: string, requestedRole?: string) {
    if (!idToken || typeof idToken !== 'string') {
      throw new ValidationError("Google ID token is required");
    }
    const role = normalizeAuthRole(requestedRole, 'user');
    const profile = await verifyGoogleIdToken(idToken);
    if (!profile.emailVerified) {
      throw new UnauthorizedError("Google account email is not verified");
    }
    const email = profile.email;
    const name = profile.name;
    let id = "";
    if (role === 'partner') {
      let partner = await prisma.partner.findFirst({ where: { email } });
      if (!partner) {
        const newPartnerData: any = {
          email,
          phone_number: email,
          kyc_status: 'unverified',
          total_earnings: 0.0
        };
        partner = await prisma.partner.create({
          data: newPartnerData
        });
      }
      id = partner.partner_id;
    } else {
      let user = await prisma.user.findFirst({ where: { email } });
      if (!user) {
        user = await prisma.user.create({
          data: {
            email,
            phone_number: email,
            name,
            status: "Active",
            total_bookings: 0,
            total_spend: 0.0
          }
        });
      }
      id = user.user_id;
      // Link the Google identity so future logins resolve to this account.
      const existingLink = await prisma.oAuthIdentity.findFirst({
        where: { user_id: id, provider: 'google', provider_user_id: profile.sub },
      });
      if (!existingLink) {
        await prisma.oAuthIdentity.create({
          data: { user_id: id, provider: 'google', provider_user_id: profile.sub },
        });
      }
    }

    const { accessToken, refreshToken } = await createSession(id, role);

    return { accessToken, refreshToken };
  }

  /**
   * OTP verification (P0): no backdoors, hashed comparison, expiry,
   * single-use (all codes for the phone are invalidated on success),
   * and a maximum number of attempts before a fresh code is required.
   */
  public static async verifyOtp(phoneNumber: string, otp: string, role: string) {
    if (!phoneNumber || !otp) {
      throw new ValidationError("Phone number and OTP are required");
    }
    const safeRole = normalizeAuthRole(role, 'user');

    const otpLog = await prisma.otpLog.findFirst({
      where: { phone_number: phoneNumber, expires_at: { gte: new Date() } },
      orderBy: { expires_at: 'desc' }
    });
    if (!otpLog) {
      // Generic message avoids account/code enumeration.
      throw new ValidationError("Invalid or expired OTP");
    }
    if (otpLog.attempt_count >= env.OTP_MAX_ATTEMPTS) {
      await prisma.otpLog.deleteMany({ where: { phone_number: phoneNumber } });
      throw new ValidationError("Too many incorrect attempts. Please request a new OTP.");
    }
    const matches = await bcrypt.compare(otp, otpLog.otp_hash);
    if (!matches) {
      await prisma.otpLog.update({
        where: { otp_id: otpLog.otp_id },
        data: { attempt_count: { increment: 1 } }
      });
      throw new ValidationError("Invalid or expired OTP");
    }

    // Single-use: invalidate every outstanding code for this phone number.
    await prisma.otpLog.deleteMany({ where: { phone_number: phoneNumber } });

    let id = "";
    let name = "";
    if (safeRole === 'partner') {
      let partner = await prisma.partner.findFirst({
        where: {
          OR: [
            { email: phoneNumber },
            { phone_number: phoneNumber }
          ]
        }
      });
      if (!partner) {
        partner = await prisma.partner.create({
          data: {
            phone_number: phoneNumber,
            email: phoneNumber.includes('@') ? phoneNumber : null,
            kyc_status: 'unverified', // Start as unverified by default
            total_earnings: 0.0
          }
        });
      }
      id = partner.partner_id;
      name = "Venue Partner";
    } else {
      let user = await prisma.user.findFirst({
        where: {
          OR: [
            { email: phoneNumber },
            { phone_number: phoneNumber }
          ]
        }
      });
      if (!user) {
        user = await prisma.user.create({
          data: {
            phone_number: phoneNumber,
            email: phoneNumber.includes('@') ? phoneNumber : null,
            name: "Athlete User",
            status: "Active",
            total_bookings: 0,
            total_spend: 0.0
          }
        });
      }
      id = user.user_id;
      name = user.name || "Athlete User";
    }

    const { accessToken, refreshToken } = await createSession(id, safeRole);

    return {
      accessToken,
      refreshToken,
      user: {
        id,
        phone_number: phoneNumber,
        name,
        role: safeRole
      }
    };
  }

  /** P2-7: rotate a refresh token into a fresh pair (replay-safe). */
  public static async refreshAccessToken(refreshToken: string) {
    return refreshSession(refreshToken);
  }

  /** P2-7: revoke the presented refresh session (idempotent logout). */
  public static async logout(refreshToken: string) {
    return revokeSession(refreshToken);
  }

  /** P2-3: user-initiated refund for own booking (server-computed amount). */
  public static async requestRefund(userId: string, bookingId: string) {
    return requestBookingRefund({ bookingId, userId });
  }

  // 2. User/Partner Profiles
  public static async getProfile(id: string, role: string) {
    if (role === 'partner') {
      const partner = await prisma.partner.findUnique({
        where: { partner_id: id },
        include: { venues: true, partner_documents: true }
      });
      if (!partner) throw new NotFoundError("Partner profile not found");
      // Own profile: bank display allowed, credentials never leave the server.
      return toOwnerPartner(partner);
    } else {
      const user = await prisma.user.findUnique({
        where: { user_id: id },
        include: { user_milestones: { include: { coupon: true } } }
      });
      if (!user) throw new NotFoundError("User profile not found");
      return toSelfUser(user);
    }
  }

  public static async updateProfile(id: string, data: any, role: string) {
    if (role === 'partner') {
      const updateData: any = {};
      if (data.fcm_token !== undefined) updateData.fcm_token = data.fcm_token;
      if (data.phone_number !== undefined) updateData.phone_number = data.phone_number;
      if (data.email !== undefined) updateData.email = data.email;
      if (data.avatar_url !== undefined) updateData.avatar_url = data.avatar_url;

      if (data.bank_name !== undefined || data.bank_account_no !== undefined || data.bank_ifsc !== undefined) {
        const partner = await prisma.partner.findUnique({ where: { partner_id: id } });
        if (!partner) throw new NotFoundError("Partner profile not found");

        const isFirstTime = !partner.bank_account_no || partner.bank_account_no.trim() === '';
        
        if (isFirstTime) {
          updateData.bank_name = data.bank_name;
          updateData.bank_account_no = data.bank_account_no;
          updateData.bank_ifsc = data.bank_ifsc;
          updateData.bank_status = 'approved';
        } else {
          updateData.temp_bank_name = data.bank_name;
          updateData.temp_bank_account_no = data.bank_account_no;
          updateData.temp_bank_ifsc = data.bank_ifsc;
          updateData.bank_status = 'pending';
        }
      }

      return toOwnerPartner(await prisma.partner.update({
        where: { partner_id: id },
        data: updateData
      }));
    } else {
      const updateData: any = {};
      if (data.name !== undefined) updateData.name = data.name;
      if (data.email !== undefined) updateData.email = data.email;
      if (data.fcm_token !== undefined) updateData.fcm_token = data.fcm_token;
      if (data.phone_number !== undefined) updateData.phone_number = data.phone_number;
      if (data.city !== undefined) updateData.city = data.city;
      if (data.state !== undefined) updateData.state = data.state;
      if (data.avatar_url !== undefined) updateData.avatar_url = data.avatar_url;
      if (data.password !== undefined && data.password !== null && data.password.trim() !== '') {
        updateData.password_hash = await bcrypt.hash(data.password, 10);
      }
      return toSelfUser(await prisma.user.update({
        where: { user_id: id },
        data: updateData
      }));
    }
  }

  public static async deleteProfile(id: string, role: string) {
    // P2-8: anonymize, never hard-delete. Financial/audit history
    // (bookings, transactions, disputes, reviews, settlements) stays intact
    // while credentials, sessions, tokens, and PII are removed/disabled.
    if (role === 'partner') {
      await prisma.venue.updateMany({ where: { partner_id: id }, data: { status: 'unlisted' } });
      await revokeAllSessions(id);
      await prisma.partner.update({
        where: { partner_id: id },
        data: {
          phone_number: `deleted-partner-${id}`,
          email: `deleted-partner-${id}@athletepov.com`,
          avatar_url: null,
          fcm_token: null,
          password_hash: null,
          kyc_status: 'deleted',
          gst_number: null,
          pan_number: null,
          aadhaar_number: null,
          bank_name: null,
          bank_account_no: null,
          bank_ifsc: null,
          temp_bank_name: null,
          temp_bank_account_no: null,
          temp_bank_ifsc: null,
        }
      });
      return { deleted: true, anonymized: true };
    } else {
      const user = await prisma.user.findUnique({ where: { user_id: id } });
      await revokeAllSessions(id);
      if (user) {
        await prisma.otpLog.deleteMany({ where: { phone_number: user.phone_number } }).catch(() => undefined);
        if (user.email) {
          await prisma.otpLog.deleteMany({ where: { phone_number: user.email } }).catch(() => undefined);
        }
      }
      await prisma.oAuthIdentity.deleteMany({ where: { user_id: id } }).catch(() => undefined);
      await prisma.user.update({
        where: { user_id: id },
        data: {
          phone_number: `deleted-user-${id}`,
          email: null,
          name: 'Deleted Athlete',
          password_hash: null,
          fcm_token: null,
          avatar_url: null,
          city: null,
          state: null,
          status: 'Deleted',
        }
      });
      return { deleted: true, anonymized: true };
    }
  }

  // 3. Wishlists
  public static async getWishlist(userId: string) {
    return prisma.wishlist.findMany({
      where: { user_id: userId },
      include: { venue: true }
    });
  }

  public static async toggleWishlist(userId: string, venueId: string) {
    const existing = await prisma.wishlist.findUnique({
      where: { user_id_venue_id: { user_id: userId, venue_id: venueId } }
    });

    if (existing) {
      await prisma.wishlist.delete({
        where: { user_id_venue_id: { user_id: userId, venue_id: venueId } }
      });
      return { wishlisted: false };
    } else {
      await prisma.wishlist.create({
        data: { user_id: userId, venue_id: venueId }
      });
      return { wishlisted: true };
    }
  }

  // 4. Venues & Slots Catalog
  public static async getVenues(city?: string, sport?: string, lat?: string, lng?: string) {
    const filter: any = { status: "listed" };
    if (sport) {
      filter.sport_types = { has: sport };
    }
    const venues = await prisma.venue.findMany({
      where: filter,
      // Public listing: partner bank/KYC identity fields must never leak.
      include: { partner: { select: SAFE_PARTNER_PUBLIC_SELECT } }
    });

    if (lat && lng) {
      const userLat = parseFloat(lat);
      const userLng = parseFloat(lng);
      if (!isNaN(userLat) && !isNaN(userLng)) {
        const calculateDistance = (lat1: number, lon1: number, lat2: number, lon2: number): number => {
          const R = 6371; // Earth radius in km
          const dLat = (lat2 - lat1) * Math.PI / 180;
          const dLon = (lon2 - lon1) * Math.PI / 180;
          const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
          const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
          return R * c;
        };

        const mappedVenues = venues.map((venue: any) => {
          // Only real database coordinates are ever used. Venues without
          // stored coordinates get nulls (never demo-city guesses and never
          // the user's own location as venue coords) so clients can honestly
          // report "distance unavailable" instead of a fabricated number.
          const rawLat = venue.latitude !== null && venue.latitude !== undefined && venue.latitude !== ''
            ? Number(venue.latitude)
            : NaN;
          const rawLng = venue.longitude !== null && venue.longitude !== undefined && venue.longitude !== ''
            ? Number(venue.longitude)
            : NaN;
          if (!Number.isFinite(rawLat) || !Number.isFinite(rawLng)) {
            return { ...venue, latitude: null, longitude: null, distance: null };
          }
          const dist = calculateDistance(userLat, userLng, rawLat, rawLng);
          return {
            ...venue,
            latitude: rawLat,
            longitude: rawLng,
            distance: parseFloat(dist.toFixed(2))
          };
        });

        // Sort by nearest first (display all venues near or far).
        // Venues without coordinates sort last instead of first (0 km).
        return mappedVenues
          .sort((a: any, b: any) => (a.distance ?? Number.POSITIVE_INFINITY) - (b.distance ?? Number.POSITIVE_INFINITY));
      }
    }

    return venues;
  }

  public static async getVenueDetails(venueId: string) {
    const venue = await prisma.venue.findUnique({
      where: { venue_id: venueId },
      include: {
        // Public reviews: reviewer identity limited to public card.
        reviews: { include: { user: { select: SAFE_USER_PUBLIC_SELECT } } },
        tournaments: true
      }
    });
    if (!venue) throw new NotFoundError("Venue not found");
    return venue;
  }

  public static async getVenueSlots(venueId: string, dateStr: string) {
    const date = new Date(dateStr);
    return prisma.slot.findMany({
      where: {
        venue_id: venueId,
        date: date
      },
      orderBy: { start_time: 'asc' }
    });
  }

  // 5. Bookings & Payments
  /**
   * Atomic slot reservation (P0): the slot is marked `booked` ONLY if it is
   * still `available`, in a single UPDATE. Concurrent requests for the same
   * slot: exactly one wins, the rest get HTTP 409. PostgreSQL is the
   * correctness guarantee (Redis may be used as an optimization elsewhere).
   */
  public static async createBooking(userId: string, venueId: string, slotId: string, paymentMode: string, couponCode?: string) {
    if (!slotId || !venueId) throw new ValidationError("Venue and slot are required");

    const reserve = await prisma.slot.updateMany({
      where: { slot_id: slotId, status: 'available' },
      data: { status: 'booked' }
    });
    if (reserve.count === 0) {
      throw new ConflictError("Slot is already booked or blocked", "SLOT_UNAVAILABLE");
    }

    try {
      const slot = await prisma.slot.findUnique({
        where: { slot_id: slotId },
        include: { venue: true }
      });
      if (!slot) throw new NotFoundError("Slot not found");
      if (slot.venue_id !== venueId) {
        throw new ValidationError("Slot does not belong to the selected venue");
      }

    let appliedCoupon: any = null;
    const now = new Date();
    if (couponCode) {
      // P2-4: fast-fail validation; the authoritative locked check happens
      // inside the booking transaction via claimCouponUsage.
      const coupon = await prisma.coupon.findUnique({ where: { code: couponCode } });
      if (!coupon || !coupon.is_active) throw new ValidationError("Coupon is not active");
      if (new Date(coupon.valid_from) > now || new Date(coupon.valid_until) < now) {
        throw new ValidationError("Coupon is expired or not yet valid");
      }
      if (Number(coupon.min_order_value || 0) > Number(slot.price)) {
        throw new ValidationError("Coupon minimum order value not met");
      }
      appliedCoupon = coupon;
    }

    const slotPrice = Number(slot.price);
    const eticketCode = `APV-${Date.now().toString(36).toUpperCase()}-${randomInt(100000, 1000000)}`;
    const bookingStatus = paymentMode === 'free' ? BOOKING_STATUS.CONFIRMED : BOOKING_STATUS.PENDING;
    // P2-1: server-side payment deadline for unpaid bookings.
    const expiresAt = bookingStatus === BOOKING_STATUS.PENDING
      ? new Date(now.getTime() + env.BOOKING_EXPIRY_MINUTES * 60 * 1000)
      : null;

    let booking;
    try {
      // P2-4: coupon claim + pricing + booking + redemption commit atomically.
      // Pricing is derived INSIDE the transaction from the row-locked coupon
      // so the charged amounts always match the claimed coupon state.
      booking = await prisma.$transaction(async (tx) => {
        let txDiscount = 0.0;
        if (appliedCoupon) {
          // Row-locked claim (global + per-user limits race-safe).
          const { coupon: freshCoupon } = await claimCouponUsage(tx, {
            couponId: appliedCoupon.coupon_id,
            userId,
            now,
          });
          appliedCoupon = freshCoupon;
          txDiscount = computeCouponDiscount(
            { discount_type: freshCoupon.discount_type, discount_value: Number(freshCoupon.discount_value), max_discount: freshCoupon.max_discount != null ? Number(freshCoupon.max_discount) : null },
            slotPrice
          );
        }

        const bookingPrice = Math.max(0, slotPrice - txDiscount);
        // Platform revenue calculations (unchanged formulas).
        const convenienceFee = Number((bookingPrice * 0.04).toFixed(2));
        const commissionAmount = Number((bookingPrice * 0.03).toFixed(2));
        const gstAmount = Number((commissionAmount * 0.18).toFixed(2));
        const partnerAmount = Number((bookingPrice - commissionAmount).toFixed(2));

        let onlineAmount = 0.0;
        let venueAmount = 0.0;
        if (paymentMode === 'pay_at_venue') {
          onlineAmount = Number((bookingPrice * 0.30 + convenienceFee + gstAmount).toFixed(2));
          venueAmount = Number((bookingPrice * 0.70).toFixed(2));
        } else {
          onlineAmount = Number((bookingPrice + convenienceFee + gstAmount).toFixed(2));
          venueAmount = 0.0;
        }

        const created = await tx.booking.create({
          data: {
            booking_id: randomUUID(),
            user_id: userId,
            venue_id: venueId,
            slot_id: slotId,
            status: bookingStatus,
            payment_mode: paymentMode,
            eticket_code: eticketCode,
            convenience_fee: convenienceFee,
            commission_amount: commissionAmount,
            gst_amount: gstAmount,
            partner_amount: partnerAmount,
            online_amount: onlineAmount,
            venue_amount: venueAmount,
            expires_at: expiresAt,
          }
        });
        if (appliedCoupon) {
          // Every successful claim writes exactly one redemption ledger row,
          // even for zero-discount coupons (per-user limits + rollback need
          // the row). Same transaction: booking failure rolls all of it back.
          await recordCouponRedemption(tx, {
            couponId: appliedCoupon.coupon_id,
            userId,
            bookingId: created.booking_id,
            discountAmount: txDiscount,
          });
        }
        return created;
      });
    } catch (err) {
      // Booking row failed: release the reservation so the slot is not
      // permanently blocked by a failed/abandoned request.
      // (Coupon increments roll back with the transaction automatically.)
      await prisma.slot.updateMany({
        where: { slot_id: slotId, status: 'booked' },
        data: { status: 'available' }
      });
      throw err;
    }

    WebSocketService.broadcast('bookings', toBookingEvent(booking));
    const slotObj = await prisma.slot.findUnique({ where: { slot_id: slotId } });
    if (slotObj) {
      WebSocketService.broadcast('slots', [slotObj]);
    }

    return booking;
    } catch (err) {
      // Any failure after the atomic reservation must not leave the slot
      // stuck as booked without a booking row (validation errors etc.).
      // A successful booking returns above, so reaching here means no booking.
      if (err instanceof NotFoundError || err instanceof ValidationError) {
        await prisma.slot.updateMany({
          where: { slot_id: slotId, status: 'booked' },
          data: { status: 'available' }
        });
      }
      throw err;
    }
  }

  /**
   * Payment order creation (P0): amount comes from the server-side booking
   * row, never the client. Existing pending orders are reused so retries do
   * not create duplicate transactions. No mock fallback in production.
   */
  public static async initiatePayment(bookingId: string, userId: string) {
    const booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    if (!booking) throw new NotFoundError("Booking not found");
    if (booking.user_id !== userId) throw new ForbiddenError("You do not own this booking");
    // P2-1/P2-2: no payment orders for terminal bookings.
    if (booking.status === BOOKING_STATUS.EXPIRED) {
      throw new ConflictError("Booking session expired. Please create a new booking.", "BOOKING_EXPIRED");
    }
    if (booking.status !== BOOKING_STATUS.PENDING && booking.status !== BOOKING_STATUS.CONFIRMED) {
      throw new ConflictError(`Payments not allowed for booking status ${booking.status}`, "ILLEGAL_STATUS_TRANSITION");
    }
    if (booking.status === 'CONFIRMED') {
      const confirmed = await prisma.transaction.findFirst({
        where: { booking_id: bookingId, txn_status: 'success' },
        orderBy: { created_at: 'desc' },
      });
      return {
        orderId: confirmed?.razorpay_order_id,
        amount: booking.online_amount,
        currency: RAZORPAY_CURRENCY,
        alreadyPaid: true,
      };
    }

    const pending = await prisma.transaction.findFirst({
      where: { booking_id: bookingId, txn_status: 'pending' },
      orderBy: { created_at: 'desc' },
    });
    if (pending) {
      const { keyId } = await resolveRazorpayKeys();
      const settings = await AdminService.getSettings();
      return {
        orderId: pending.razorpay_order_id,
        amount: booking.online_amount,
        currency: RAZORPAY_CURRENCY,
        key: keyId || settings.razorpayKeyId,
      };
    }

    const { keyId, keySecret } = await resolveRazorpayKeys();
    if (!keyId || !keySecret) {
      if (!isMockPaymentsAllowed()) {
        throw new ValidationError("Payment gateway is not configured. Please try again later.");
      }
      const orderId = `order_mock_${Date.now()}_${randomInt(100000, 1000000)}`;
      await prisma.transaction.create({
        data: {
          booking_id: bookingId,
          razorpay_order_id: orderId,
          txn_type: "capture",
          txn_status: "pending",
          amount: booking.online_amount
        }
      });
      return { orderId, amount: booking.online_amount, currency: RAZORPAY_CURRENCY, mock: true };
    }

    let orderId: string;
    try {
      const amountInPaise = toPaise(Number(booking.online_amount));
      const response = await fetch('https://api.razorpay.com/v1/orders', {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${razorpayBasicAuth(keyId, keySecret)}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          amount: amountInPaise,
          currency: RAZORPAY_CURRENCY,
          receipt: bookingId
        })
      });
      const rzpOrder: any = await response.json();
      if (!rzpOrder || !rzpOrder.id) {
        throw new ValidationError("Payment gateway did not return an order. Please try again.");
      }
      if (Number(rzpOrder.amount) !== amountInPaise) {
        throw new ValidationError("Payment gateway order amount mismatch. Please try again.");
      }
      orderId = rzpOrder.id;
    } catch (err: any) {
      if (err instanceof ValidationError || err instanceof NotFoundError || err instanceof ForbiddenError) throw err;
      throw new ValidationError("Failed to create payment order. Please try again.");
    }

    await prisma.transaction.create({
      data: {
        booking_id: bookingId,
        razorpay_order_id: orderId,
        txn_type: "capture",
        txn_status: "pending",
        amount: booking.online_amount
      }
    });

    return { orderId, amount: booking.online_amount, currency: RAZORPAY_CURRENCY, key: keyId };
  }

  /**
   * Payment verification (P0): the client is NEVER trusted.
   * Requires the Razorpay signature (HMAC-SHA256 order|payment), verifies the
   * payment object server-side (order binding, captured status, exact server
   * amount, currency, user binding), rejects reused payment IDs, and applies
   * all state changes atomically. Repeat calls are idempotent.
   */
  public static async verifyPayment(
    bookingId: string,
    userId: string,
    razorpayOrderId: string,
    razorpayPaymentId: string,
    razorpaySignature?: string
  ) {
    if (!bookingId || !razorpayOrderId || !razorpayPaymentId) {
      throw new ValidationError("Booking, order and payment identifiers are required");
    }
    const txn = await prisma.transaction.findFirst({
      where: { booking_id: bookingId, razorpay_order_id: razorpayOrderId }
    });
    if (!txn) throw new NotFoundError("Transaction record not found");

    const bookingRow = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    if (!bookingRow) throw new NotFoundError("Booking not found");
    if (bookingRow.user_id !== userId) throw new ForbiddenError("You do not own this booking");

    // Idempotency: already confirmed / already processed.
    if (txn.txn_status === 'success' || bookingRow.status === 'CONFIRMED') {
      const current = await prisma.booking.findUnique({
        where: { booking_id: bookingId },
        include: { user: true, venue: { include: { partner: true } }, slot: true },
      });
      return { ...sanitizeBookingForResponse(current), alreadyProcessed: true };
    }
    const paymentGuard = await redis.set(BOOKING_PAYMENT_GUARD_KEY(razorpayPaymentId), bookingId, { NX: true, EX: 86400 * 30 });
    if (paymentGuard === null) {
      throw new ConflictError("This payment has already been processed", "PAYMENT_REUSED");
    }

    try {
      const mockOrder = isMockOrderId(razorpayOrderId);
      const mockPayment = isMockPaymentId(razorpayPaymentId);
      if (mockOrder || mockPayment) {
        // Simulated payments: explicit dev-only opt-in, never in production.
        if (!isMockPaymentsAllowed()) {
          throw new ValidationError("Payment verification failed");
        }
      } else {
        const { keySecret } = await resolveRazorpayKeys();
        if (!keySecret) throw new ValidationError("Payment gateway is not configured");
        if (!razorpaySignature || !verifyRazorpayPaymentSignature(razorpayOrderId, razorpayPaymentId, razorpaySignature, keySecret)) {
          throw new ValidationError("Payment signature verification failed");
        }
        const { keyId } = await resolveRazorpayKeys();
        let paymentDetails: any;
        try {
          paymentDetails = await fetchRazorpayPayment(razorpayPaymentId, keyId, keySecret);
        } catch (_) {
          throw new ValidationError("Could not verify payment with the gateway. Please try again.");
        }
        if (!paymentDetails || paymentDetails.order_id !== razorpayOrderId) {
          throw new ValidationError("Payment is not linked to this booking's order");
        }
        if (paymentDetails.status !== 'captured' && paymentDetails.status !== 'authorized') {
          throw new ValidationError("Payment is not successful");
        }
        if (String(paymentDetails.currency || '').toUpperCase() !== RAZORPAY_CURRENCY) {
          throw new ValidationError("Payment currency mismatch");
        }
        const expectedPaise = toPaise(Number(bookingRow.online_amount));
        if (Number(paymentDetails.amount) !== expectedPaise) {
          throw new ValidationError("Payment amount does not match the booking amount");
        }
        // One Razorpay payment must never confirm two bookings.
        const reused = await prisma.transaction.findFirst({
          where: {
            razorpay_payment_id: razorpayPaymentId,
            txn_status: 'success',
            booking_id: { not: bookingId },
          },
        });
        if (reused) {
          throw new ConflictError("This payment has already been used for another booking", "PAYMENT_REUSED");
        }
      }

      const result = await prisma.$transaction(async (tx) => {
        // P2-1/P2-2: confirm ONLY a live PENDING booking. Expired (or
        // concurrently settled) bookings never confirm through this path.
        const now = new Date();
        const confirmed = await tx.booking.updateMany({
          where: {
            booking_id: bookingId,
            status: BOOKING_STATUS.PENDING,
            OR: [{ expires_at: null }, { expires_at: { gt: now } }],
          },
          data: { status: BOOKING_STATUS.CONFIRMED, expires_at: null },
        });
        if (confirmed.count === 0) {
          throw new ConfirmRaceError();
        }
        await tx.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: razorpayPaymentId, txn_status: "success" }
        });
        const booking = await tx.booking.findUnique({
          where: { booking_id: bookingId },
          include: {
            user: true,
            venue: { include: { partner: true } },
            slot: true
          }
        });
        if (!booking) throw new NotFoundError("Booking not found");
        const updatedUser = await tx.user.update({
          where: { user_id: booking.user_id },
          data: {
            total_bookings: { increment: 1 },
            total_spend: { increment: booking.online_amount }
          }
        });
        return { booking, updatedUser };
      }).catch(async (err) => {
        if (!(err instanceof ConfirmRaceError)) throw err;
        // Another writer won (confirm/cancel/expire raced verification).
        const current = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
        if (current?.status === BOOKING_STATUS.CONFIRMED) {
          const full = await prisma.booking.findUnique({
            where: { booking_id: bookingId },
            include: { user: true, venue: { include: { partner: true } }, slot: true },
          });
          return { booking: full, updatedUser: null, idempotent: true } as any;
        }
        // P2-1: payment is real (HMAC + gateway verified above) but the
        // booking is no longer confirmable (EXPIRED or past-deadline PENDING).
        // Record the payment truthfully; NEVER confirm. The caller receives
        // BOOKING_EXPIRED and may pursue a refund via the refund endpoint.
        if (current && current.status === BOOKING_STATUS.PENDING && current.expires_at && current.expires_at <= new Date()) {
          await prisma.booking.updateMany({
            where: { booking_id: bookingId, status: BOOKING_STATUS.PENDING },
            data: { status: BOOKING_STATUS.EXPIRED, expires_at: null },
          });
          await prisma.slot.updateMany({
            where: { slot_id: current.slot_id, status: 'booked' },
            data: { status: 'available' },
          });
        }
        await prisma.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: razorpayPaymentId, txn_status: 'success' },
        });
        throw new ConfirmExpiredError();
      });

      // Process Rewards & Milestones (non-fatal; skipped on idempotent replay).
      if (!result.idempotent) {
        try {
          await ClientService.processRewardsAndMilestones(result.updatedUser, result.booking);
        } catch (err) {
          console.error("Error processing rewards/milestones:", err);
        }
      }

      const { booking } = result;
      if (result.idempotent) {
        return { ...sanitizeBookingForResponse(booking), alreadyProcessed: true };
      }
      // P2-9: persisted + deduped notifications (invalid tokens cleaned).
      {
        const slotTime = `${booking.slot.start_time} - ${booking.slot.end_time}`;
        await notifyUser(
          booking.user_id, 'booking',
          "Booking Confirmed!",
          `Your booking at ${booking.venue.name} for slot ${slotTime} is confirmed.`,
          `booking-confirmed:${bookingId}`
        ).catch(() => undefined);
        const confirmPartnerId = (booking.venue as any)?.partner?.partner_id ?? (booking.venue as any)?.partner_id;
        if (confirmPartnerId && (booking.venue as any)?.partner?.fcm_token) {
          await notifyPartner(
            confirmPartnerId, 'booking',
            "New Booking Received!",
            `${booking.user.name || 'An athlete'} has booked slot ${slotTime} at ${booking.venue.name}.`,
            `booking-received:${bookingId}`
          ).catch(() => undefined);
        }
      }

      // B1: global broadcast carries ONLY the minimal scalar event. The
      // affected user + partner each get a targeted event instead.
      const bookingEvent = toBookingEvent(booking);
      const bookingPrivateEvent = toBookingEvent(booking, { includePrivate: true });
      const partnerId = (booking.venue as any)?.partner?.partner_id ?? (booking.venue as any)?.partner_id;
      WebSocketService.broadcast('bookings', bookingEvent);
      WebSocketService.emitToUser(booking.user_id, 'booking_confirmed', bookingPrivateEvent);
      if (partnerId) {
        WebSocketService.emitToUser(partnerId, 'booking_received', bookingPrivateEvent);
      }
      const slot = await prisma.slot.findUnique({ where: { slot_id: booking.slot_id } });
      if (slot) {
        WebSocketService.broadcast('slots', [slot]);
      }

      return sanitizeBookingForResponse(booking);
    } catch (err) {
      // Release the idempotency guard on genuine verification failures so a
      // legitimate retry with a NEW payment can proceed. Confirmed bookings
      // never reach here (returned above).
      if (err instanceof ValidationError) {
        await redis.del(BOOKING_PAYMENT_GUARD_KEY(razorpayPaymentId));
      }
      if (err instanceof ConfirmExpiredError) {
        throw new ConflictError("Booking session expired before payment confirmation. Please rebook; a refund can be requested for the captured payment.", "BOOKING_EXPIRED");
      }
      throw err;
    }
  }

  /**
   * Razorpay webhook (P0): signature verified over the RAW body, processing
   * idempotent per event/payment/order. Handles payment.captured (confirms
   * the booking even if the app was closed) and payment.failed (marks txn).
   */
  public static async handleRazorpayWebhook(rawBody: Buffer, signature: string | undefined) {
    const webhookSecret = env.RAZORPAY_WEBHOOK_SECRET || (await AdminService.getSettings()).razorpayWebhookSecret;
    if (!webhookSecret) {
      return { ignored: true, reason: 'webhook-secret-not-configured' };
    }
    if (!verifyRazorpayWebhookSignature(rawBody, signature, webhookSecret)) {
      throw new ValidationError("Invalid webhook signature");
    }
    let event: any;
    try {
      event = JSON.parse(rawBody.toString('utf8'));
    } catch (_) {
      throw new ValidationError("Invalid webhook payload");
    }
    const eventId: string | undefined = event?.id;
    const type: string | undefined = event?.event;
    // P2-3: refund events carry a refund entity (not a payment entity).
    if (type === 'refund.processed' || type === 'refund.failed') {
      const refund = (event as any)?.payload?.refund?.entity;
      if (!refund?.id) {
        return { ignored: true, reason: 'unsupported-event' };
      }
      const refundGuardKey = eventId ? WEBHOOK_EVENT_GUARD_KEY(eventId) : BOOKING_PAYMENT_GUARD_KEY(refund.id);
      const refundFirst = await redis.set(refundGuardKey, type, { NX: true, EX: 86400 * 30 });
      if (refundFirst === null) {
        return { duplicate: true, event: type };
      }
      const { applyRefundWebhookEvent } = await import('../../shared/services/refunds.js');
      const outcome = await applyRefundWebhookEvent({
        type,
        refundId: refund.id,
        paymentId: refund.payment_id,
        amountPaise: refund.amount != null ? Number(refund.amount) : undefined,
      });
      return { processed: outcome.processed, event: type, reason: outcome.reason };
    }
    const payment = event?.payload?.payment?.entity;
    const orderId: string | undefined = payment?.order_id;
    const paymentId: string | undefined = payment?.id;
    if (!type || !orderId || !paymentId) {
      return { ignored: true, reason: 'unsupported-event' };
    }

    const guardKey = eventId ? WEBHOOK_EVENT_GUARD_KEY(eventId) : BOOKING_PAYMENT_GUARD_KEY(paymentId);
    const first = await redis.set(guardKey, type, { NX: true, EX: 86400 * 30 });
    if (first === null) {
      return { duplicate: true, event: type };
    }

    const txn = await prisma.transaction.findFirst({ where: { razorpay_order_id: orderId } });
    if (!txn) {
      return { ignored: true, reason: 'unknown-order' };
    }
    if (type === 'payment.captured' || type === 'payment.authorized') {
      // B3 state machine: verify amount/currency against the server-side
      // booking row, and only ever PENDING -> CONFIRMED atomically.
      const bookingRow = await prisma.booking.findUnique({ where: { booking_id: txn.booking_id } });
      if (!bookingRow) {
        return { ignored: true, reason: 'unknown-booking' };
      }
      const amountOk = Number(payment?.amount) === toPaise(Number(bookingRow.online_amount));
      const currencyOk = String(payment?.currency || RAZORPAY_CURRENCY).toUpperCase() === RAZORPAY_CURRENCY;
      const transition = resolveWebhookTransition(bookingRow.status, amountOk, currencyOk, txn.txn_status);

      if (transition.action === 'duplicate') {
        return { duplicate: true, event: type };
      }
      if (transition.action === 'record_mismatch') {
        // Money event recorded truthfully, booking untouched.
        await prisma.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: paymentId, txn_status: 'failed' },
        });
        console.warn(`Webhook ${transition.reason} for booking ${txn.booking_id} (order ${orderId}); booking left ${bookingRow.status}.`);
        return { processed: true, event: type, bookingId: txn.booking_id, confirmed: false, reason: transition.reason };
      }
      if (transition.action === 'converge') {
        // Booking already CONFIRMED via another path: converge the ledger
        // without duplicating stats/notifications.
        await prisma.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: paymentId, txn_status: 'success' },
        });
        return { processed: true, event: type, bookingId: txn.booking_id, confirmed: false, reason: transition.reason };
      }
      if (transition.action === 'record_truthful') {
        // Genuine capture for a booking that may no longer confirm
        // (e.g. CANCELLED after slot release): record payment success for
        // finance reconciliation, NEVER touch booking/slot/stats.
        await prisma.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: paymentId, txn_status: 'success' },
        });
        console.warn(`Webhook capture for non-pending booking ${txn.booking_id} (status ${bookingRow.status}); payment recorded, booking untouched.`);
        return { processed: true, event: type, bookingId: txn.booking_id, confirmed: false, reason: transition.reason };
      }

      // action === 'confirm': atomic PENDING -> CONFIRMED. The conditional
      // update is the correctness guarantee under concurrent webhooks.
      // P2-1: a PENDING row past its server-side deadline must expire instead
      // of confirming, even if the sweeper has not run yet.
      if (bookingRow.expires_at && bookingRow.expires_at <= new Date()) {
        await prisma.booking.updateMany({
          where: { booking_id: txn.booking_id, status: BOOKING_STATUS.PENDING },
          data: { status: BOOKING_STATUS.EXPIRED, expires_at: null },
        });
        await prisma.slot.updateMany({
          where: { slot_id: bookingRow.slot_id, status: 'booked' },
          data: { status: 'available' },
        });
        await prisma.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: paymentId, txn_status: 'success' },
        });
        console.warn(`Webhook capture arrived past expiry for booking ${txn.booking_id}; expired + payment recorded, never confirmed.`);
        return { processed: true, event: type, bookingId: txn.booking_id, confirmed: false, reason: 'past-expiry' };
      }
      const confirmResult = await prisma.$transaction(async (tx) => {
        const confirmedCount = await tx.booking.updateMany({
          where: { booking_id: txn.booking_id, status: 'PENDING' },
          data: { status: 'CONFIRMED', expires_at: null },
        });
        if (confirmedCount.count === 0) {
          // Lost a race (cancelled/confirmed concurrently): record payment
          // truthfully, do not touch booking/slot/stats.
          await tx.transaction.update({
            where: { txn_id: txn.txn_id },
            data: { razorpay_payment_id: paymentId, txn_status: 'success' },
          });
          return { raced: true };
        }
        await tx.transaction.update({
          where: { txn_id: txn.txn_id },
          data: { razorpay_payment_id: paymentId, txn_status: 'success' },
        });
        const updatedUser = await tx.user.update({
          where: { user_id: bookingRow.user_id },
          data: {
            total_bookings: { increment: 1 },
            total_spend: { increment: bookingRow.online_amount },
          },
        });
        return { raced: false, updatedUser };
      });
      if (confirmResult.raced) {
        console.warn(`Webhook confirm raced for booking ${txn.booking_id}; payment recorded, booking untouched.`);
        return { processed: true, event: type, bookingId: txn.booking_id, confirmed: false, reason: 'confirm-race' };
      }

      const booking = await prisma.booking.findUnique({
        where: { booking_id: txn.booking_id },
        include: { user: true, venue: { include: { partner: true } }, slot: true },
      });
      if (booking) {
        // B1: minimal global event + targeted delivery (never full relations).
        const bookingEvent = toBookingEvent(booking);
        const bookingPrivateEvent = toBookingEvent(booking, { includePrivate: true });
        const partnerId = (booking.venue as any)?.partner?.partner_id ?? (booking.venue as any)?.partner_id;
        WebSocketService.broadcast('bookings', bookingEvent);
        WebSocketService.emitToUser(booking.user_id, 'booking_confirmed', bookingPrivateEvent);
        if (partnerId) {
          WebSocketService.emitToUser(partnerId, 'booking_received', bookingPrivateEvent);
        }
      }
      return { processed: true, event: type, bookingId: txn.booking_id, confirmed: true };
    }
    if (type === 'payment.failed') {
      // B3-equivalent for failures: the ledger is marked failed and, ONLY when
      // the booking is still PENDING, it is transitioned PENDING -> CANCELLED
      // and its slot released. CONFIRMED / CANCELLED / EXPIRED bookings are
      // never touched, the release is conditional (no double release) and the
      // whole handler is idempotent across webhook retries.
      const outcome = await releaseBookingOnFailedPayment(txn.booking_id, txn.txn_id, paymentId);
      if (outcome.released && outcome.booking) {
        const released = outcome.booking;
        const bookingEvent = toBookingEvent(released);
        const bookingPrivateEvent = toBookingEvent(released, { includePrivate: true });
        const partnerId = (released.venue as any)?.partner_id;
        WebSocketService.broadcast('bookings', bookingEvent);
        WebSocketService.emitToUser(released.user_id, 'booking_cancelled', bookingPrivateEvent);
        if (partnerId) {
          WebSocketService.emitToUser(partnerId, 'booking_cancelled', bookingPrivateEvent);
        }
        if (outcome.slot) {
          WebSocketService.broadcast('slots', [outcome.slot]);
        }
        await notifyUser(
          released.user_id,
          'booking',
          "Payment Failed",
          "Your payment could not be completed, so the booking was cancelled and the slot released. You can book again.",
          `payment-failed:${paymentId ?? txn.txn_id}`
        ).catch(() => undefined);
      }
      return {
        processed: true,
        event: type,
        bookingId: txn.booking_id,
        released: outcome.released,
        slotReleased: outcome.slotReleased,
        bookingStatus: outcome.bookingStatus,
        reason: outcome.reason,
      };
    }
    return { ignored: true, reason: 'unsupported-event' };
  }

  public static async getBookings(userId: string) {
    return prisma.booking.findMany({
      where: { user_id: userId },
      include: {
        venue: true,
        slot: true
      },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async cancelBooking(
    bookingId: string,
    userId: string,
    opts: { pendingOnly?: boolean } = {}
  ) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: {
        slot: true,
        user: true,
        venue: {
          include: {
            partner: true
          }
        }
      }
    });

    if (!booking) throw new NotFoundError("Booking not found");
    if (booking.user_id !== userId) throw new ValidationError("Unauthorized cancellation");
    // Auto-release after a failed payment: only a booking that is STILL
    // PENDING may be released this way. If a webhook/verification confirmed it
    // in the meantime we must never cancel it here — the caller is told the
    // current status instead (409 NOT_PENDING + details.status).
    if (opts.pendingOnly && booking.status !== BOOKING_STATUS.PENDING) {
      throw new ConflictError(
        `Booking is ${booking.status}; only a PENDING booking can be auto-released.`,
        'NOT_PENDING',
        { status: booking.status }
      );
    }
    // P2-2: only live bookings cancel. EXPIRED/COMPLETED/CANCELLED reject.
    assertBookingTransition(booking.status, BOOKING_STATUS.CANCELLED);

    // Refund policy quote (March 2026 policy) via the shared helper so the
    // cancel response and the refund endpoint use identical server-side math.
    // Auto-release after a failed payment captured nothing: never quote a
    // refund the platform does not owe.
    const quote = computeRefundQuote(
      booking.online_amount, booking.convenience_fee,
      (booking.slot as any)?.date, (booking.slot as any)?.start_time, new Date()
    );
    const refundEligibility = opts.pendingOnly ? 'NO_REFUND' as const : quote.eligibility;
    const refundMessage = opts.pendingOnly
      ? 'No payment was captured — nothing to refund.'
      : quote.message;
    const estimatedRefundAmount = opts.pendingOnly ? 0 : quote.amount;

    // Conditional transition on the auto-release path: if a concurrent
    // verification/webhook changed the status after our read, this booking is
    // no longer PENDING and MUST NOT be cancelled by a payment-failure flow.
    let updated;
    if (opts.pendingOnly) {
      const flipped = await prisma.booking.updateMany({
        where: { booking_id: bookingId, status: BOOKING_STATUS.PENDING },
        data: { status: BOOKING_STATUS.CANCELLED, expires_at: null },
      });
      if (flipped.count === 0) {
        const fresh = await prisma.booking.findUnique({ where: { booking_id: bookingId }, select: { status: true } });
        throw new ConflictError(
          `Booking is ${fresh?.status ?? 'unknown'}; only a PENDING booking can be auto-released.`,
          'NOT_PENDING',
          { status: fresh?.status ?? null }
        );
      }
      updated = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    } else {
      updated = await prisma.booking.update({
        where: { booking_id: bookingId },
        data: { status: "CANCELLED" }
      });
    }

    // Release the held slot only while it is still `booked`: the slot can
    // never be released twice, and a slot re-booked by someone else is never
    // clobbered.
    await prisma.slot.updateMany({
      where: { slot_id: booking.slot_id, status: "booked" },
      data: { status: "available" }
    });
    const updatedSlot = await prisma.slot.findUnique({ where: { slot_id: booking.slot_id } });

    // The order for this booking can no longer be paid once the booking is
    // CANCELLED: record an unfinished capture attempt truthfully as `failed`
    // rather than leaving a live `pending` row in the finance ledger. A late
    // webhook/verification proving the money DID arrive still flips it to
    // `success` — the booking stays CANCELLED, i.e. a refund case, never a
    // silently resurrected confirmation.
    await prisma.transaction.updateMany({
      where: { booking_id: bookingId, txn_type: "capture", txn_status: "pending" },
      data: { txn_status: "failed" },
    });

    // P2-4/P2-7: roll the coupon claim back exactly once (idempotent,
    // concurrent-cancellation safe). Reported, never silently swallowed.
    let couponRollback: any = { rolledBack: false };
    try {
      couponRollback = await rollbackCouponForBooking(bookingId);
    } catch (err: any) {
      couponRollback = { rolledBack: false, error: err?.message || 'coupon-rollback-failed' };
    }

    // P2-3: attempt a real refund for captured payments (best-effort; the
    // booking stays cancelled regardless and the outcome is reported).
    // Auto-release after a FAILED payment never refunds: no money was captured.
    let refundStatus: any = { attempted: false };
    if (opts.pendingOnly) {
      refundStatus = { attempted: false, reason: 'NO_PAYMENT_CAPTURED' };
    } else {
      try {
        const quote = computeRefundQuote(
          booking.online_amount, booking.convenience_fee,
          (booking.slot as any)?.date, (booking.slot as any)?.start_time, new Date()
        );
        if (quote.amount > 0) {
          const outcome = await requestBookingRefund({ bookingId, userId });
          refundStatus = { attempted: true, ...outcome, refundTxn: undefined, refundId: outcome.refundTxn?.txn_id };
        } else {
          refundStatus = { attempted: false, reason: quote.eligibility };
        }
      } catch (err: any) {
        refundStatus = { attempted: true, failed: true, reason: err?.message || 'refund-failed' };
      }
    }

    const slotTime = `${booking.slot.start_time} - ${booking.slot.end_time}`;
    await notifyUser(
      booking.user_id, 'booking',
      "Booking Cancelled",
      opts.pendingOnly
        ? `Your payment for ${booking.venue.name} did not complete, so the booking was cancelled and the slot released.`
        : `Your booking at ${booking.venue.name} has been cancelled. Policy outcome: ${refundMessage}`,
      `booking-cancelled:${bookingId}`
    ).catch(() => undefined);
    const cancelPartnerId = (booking.venue as any)?.partner_id;
    if (cancelPartnerId) {
      await notifyPartner(
        cancelPartnerId, 'booking',
        "Booking Cancelled",
        `Slot ${slotTime} at ${booking.venue.name} has been cancelled and is now available.`,
        `booking-cancelled:${bookingId}:${cancelPartnerId}`
      ).catch(() => undefined);
    }

    WebSocketService.broadcast('bookings', toBookingEvent({ ...updated, venue_id: booking.venue_id, slot_id: booking.slot_id }));
    WebSocketService.emitToUser(booking.user_id, 'booking_cancelled', toBookingEvent({ ...updated, venue_id: booking.venue_id, slot_id: booking.slot_id }));
    if (cancelPartnerId) {
      WebSocketService.emitToUser(cancelPartnerId, 'booking_cancelled', toBookingEvent({ ...updated, venue_id: booking.venue_id, slot_id: booking.slot_id }));
    }
    if (updatedSlot) {
      WebSocketService.broadcast('slots', [updatedSlot]);
    }

    return {
      message: "Booking cancelled successfully",
      // Server-side truth the client can render without guessing:
      bookingStatus: updated?.status ?? BOOKING_STATUS.CANCELLED,
      slotStatus: updatedSlot?.status ?? "available",
      refundEligibility,
      refundMessage,
      estimatedRefundAmount,
      processingTime: "7-10 working days",
      refund: refundStatus,
      coupon: couponRollback,
    };
  }

  // 6. Coupons
  public static async getCoupons() {
    return prisma.coupon.findMany({
      where: { is_active: true }
    });
  }

  // 7. Tournaments
  public static async getTournaments() {
    return prisma.tournament.findMany({
      include: { venue: true }
    });
  }

  public static async registerTournament(userId: string, tournamentId: string, teamName: string) {
    if (!teamName || !teamName.trim()) throw new ValidationError("Team name is required");
    const registration = await prisma.$transaction(async (tx) => {
      const tournament = await tx.tournament.findUnique({ where: { tournament_id: tournamentId } });
      if (!tournament) throw new NotFoundError("Tournament not found");
      // P2-5: open-state + capacity pre-checks (authoritative guard below).
      const gate = canRegisterTournament(tournament.status, tournament.current_participants, tournament.max_participants);
      if (!gate.ok) {
        throw new ConflictError(`Tournament registration not allowed (${gate.reason})`, 'TOURNAMENT_NOT_OPEN');
      }
      const existing = await tx.tournamentRegistration.findUnique({
        where: { tournament_id_user_id: { tournament_id: tournamentId, user_id: userId } },
      });
      if (existing) throw new ConflictError("Already registered for this tournament", "DUPLICATE_REGISTRATION");
      // Atomic capacity claim: exactly one winner for the last slot.
      const claimed = await tx.tournament.updateMany({
        where: {
          tournament_id: tournamentId,
          status: { in: ['upcoming', 'open'] },
          current_participants: { lt: tournament.max_participants },
        },
        data: { current_participants: { increment: 1 } },
      });
      if (claimed.count === 0) {
        throw new ConflictError("Tournament is full", "TOURNAMENT_FULL");
      }
      try {
        return await tx.tournamentRegistration.create({
          data: {
            tournament_id: tournamentId,
            user_id: userId,
            team_name: teamName.trim(),
            payment_status: "paid"
          }
        });
      } catch (err: any) {
        if (err?.code === 'P2002') throw new ConflictError("Already registered for this tournament", "DUPLICATE_REGISTRATION");
        throw err;
      }
    });

    // Send notification (persisted; invalid tokens cleaned by the helper).
    const tournament = await prisma.tournament.findUnique({ where: { tournament_id: tournamentId } });
    await notifyUser(
      userId, 'tournament',
      "Tournament Registered!",
      `You have successfully registered team '${teamName.trim()}' for the ${tournament?.name ?? 'tournament'}.`,
      `tournament-registered:${tournamentId}:${userId}`
    ).catch(() => undefined);

    return registration;
  }

  /**
   * P2-5: registration cancellation frees capacity exactly once (delete +
   * guarded decrement in one transaction; repeat cancels 404 on the missing row).
   */
  public static async cancelTournamentRegistration(userId: string, tournamentId: string) {
    return prisma.$transaction(async (tx) => {
      const reg = await tx.tournamentRegistration.findUnique({
        where: { tournament_id_user_id: { tournament_id: tournamentId, user_id: userId } },
      });
      if (!reg) throw new NotFoundError("Registration not found");
      await tx.tournamentRegistration.delete({ where: { reg_id: reg.reg_id } });
      await tx.tournament.updateMany({
        where: { tournament_id: tournamentId, current_participants: { gt: 0 } },
        data: { current_participants: { decrement: 1 } },
      });
      return { cancelled: true };
    });
  }

  // 8. Notifications
  public static async getNotifications(recipientId: string, role: string) {
    return prisma.userNotification.findMany({
      where: { recipient_id: recipientId, recipient_type: role },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async readNotification(notifId: string, recipientId?: string) {
    const notif = await prisma.userNotification.findUnique({ where: { notif_id: notifId } });
    if (!notif) throw new NotFoundError("Notification not found");
    if (recipientId && notif.recipient_id !== recipientId) {
      throw new ForbiddenError("You cannot modify another user's notification");
    }
    return prisma.userNotification.update({
      where: { notif_id: notifId },
      data: { is_read: true }
    });
  }

  public static async getChatHistory(userId: string) {
    // Fetch all messages sent by this user or received by this user from/to admin
    // In this app, recipient_id or sender_id is either the user_id or the admin's hardcoded ID.
    // We can just fetch all messages involving this user_id.
    return prisma.chatMessage.findMany({
      where: {
        OR: [
          { sender_id: userId },
          { recipient_id: userId }
        ]
      },
      orderBy: { created_at: 'asc' }
    });
  }


  // 9. Content Banners
  public static async getBanners(target: string) {
    return prisma.banner.findMany({
      where: { target_app: { in: [target, 'all'] }, is_active: true },
      orderBy: { display_order: 'asc' }
    });
  }

  // Partner Services
  /**
   * Ownership guard (P0): every partner operation on a venue-scoped resource
   * must prove the venue belongs to the authenticated partner.
   */
  private static async assertPartnerVenue(partnerId: string, venueId: string) {
    const venue = await prisma.venue.findFirst({
      where: { venue_id: venueId, partner_id: partnerId }
    });
    if (!venue) throw new NotFoundError("Venue not found or unauthorized");
    return venue;
  }

  private static async assertPartnerSlotOwner(partnerId: string, slotId: string) {
    const slot = await prisma.slot.findUnique({
      where: { slot_id: slotId },
      include: { venue: true },
    });
    if (!slot || slot.venue.partner_id !== partnerId) {
      throw new NotFoundError("Slot not found or unauthorized");
    }
    return slot;
  }
  public static async getPartnerVenues(partnerId: string) {
    return prisma.venue.findMany({
      where: { partner_id: partnerId },
      include: {
        slots: true,
        bookings: true
      }
    });
  }

  public static async createPartnerVenue(partnerId: string, data: any) {
    return prisma.venue.create({
      data: {
        partner_id: partnerId,
        name: data.name,
        sport_types: data.sportTypes || [],
        base_price: Number(data.basePrice),
        slot_mode: data.slotMode || '60m',
        status: 'unlisted', // Requires admin approval
        amenities: data.amenities || [],
        images: data.images || [],
        address: data.address || null,
        contact_phone: data.contactPhone || null,
        latitude: data.latitude != null ? Number(data.latitude) : null,
        longitude: data.longitude != null ? Number(data.longitude) : null,
        opening_time: data.openingTime || '06:00',
        closing_time: data.closingTime || '22:00'
      }
    });
  }

  public static async updatePartnerVenue(partnerId: string, venueId: string, data: any) {
    const venue = await prisma.venue.findFirst({
      where: { venue_id: venueId, partner_id: partnerId }
    });
    if (!venue) throw new NotFoundError("Venue not found or unauthorized");

    return prisma.venue.update({
      where: { venue_id: venueId },
      data: {
        name: data.name,
        sport_types: data.sportTypes,
        base_price: data.basePrice ? Number(data.basePrice) : undefined,
        slot_mode: data.slotMode,
        amenities: data.amenities !== undefined ? data.amenities : undefined,
        images: data.images !== undefined ? data.images : undefined,
        address: data.address !== undefined ? data.address : undefined,
        contact_phone: data.contactPhone !== undefined ? data.contactPhone : undefined,
        latitude: data.latitude !== undefined ? (data.latitude != null ? Number(data.latitude) : null) : undefined,
        longitude: data.longitude !== undefined ? (data.longitude != null ? Number(data.longitude) : null) : undefined,
        opening_time: data.openingTime !== undefined ? data.openingTime : undefined,
        closing_time: data.closingTime !== undefined ? data.closingTime : undefined,
        status: "unlisted" // Automatically set to unlisted to require admin review/approval to list it
      }
    });
  }

  public static async getPartnerVenueSlots(venueId: string, dateStr: string, partnerId?: string) {
    if (partnerId) await ClientService.assertPartnerVenue(partnerId, venueId);
    const date = new Date(dateStr);
    if (Number.isNaN(date.getTime())) throw new ValidationError("Invalid date");
    return prisma.slot.findMany({
      where: {
        venue_id: venueId,
        date: date
      },
      orderBy: { start_time: 'asc' }
    });
  }

  public static async bulkGenerateSlots(venueId: string, dates: string[], startTime: string, endTime: string, price: number, durationMinutes: number, partnerId?: string) {
    if (partnerId) await ClientService.assertPartnerVenue(partnerId, venueId);
    if (!Array.isArray(dates) || dates.length === 0 || dates.length > 62) {
      throw new ValidationError("Provide 1-62 dates for slot generation");
    }
    if (!Number.isFinite(Number(price)) || Number(price) < 0) {
      throw new ValidationError("Invalid slot price");
    }
    if (!Number.isFinite(Number(durationMinutes)) || Number(durationMinutes) < 15 || Number(durationMinutes) > 480) {
      throw new ValidationError("Invalid slot duration");
    }
    const created = [];

    for (const dateStr of dates) {
      const date = new Date(dateStr);

      // Parse times
      const [startHour, startMin] = startTime.split(':').map(Number);
      const [endHour, endMin] = endTime.split(':').map(Number);

      let current = new Date(date);
      current.setHours(startHour, startMin, 0, 0);

      const end = new Date(date);
      end.setHours(endHour, endMin, 0, 0);

      const slotsData = [];
      while (current < end) {
        const next = new Date(current.getTime() + durationMinutes * 60000);
        if (next > end) break;

        const sTime = `${current.getHours().toString().padStart(2, '0')}:${current.getMinutes().toString().padStart(2, '0')}`;
        const eTime = `${next.getHours().toString().padStart(2, '0')}:${next.getMinutes().toString().padStart(2, '0')}`;

        slotsData.push({
          venue_id: venueId,
          date: date,
          start_time: sTime,
          end_time: eTime,
          price: price,
          status: 'available'
        });

        current = next;
      }

      for (const data of slotsData) {
        // Skip if slot already exists with same start_time, end_time, and date
        const existing = await prisma.slot.findFirst({
          where: {
            venue_id: venueId,
            date: data.date,
            start_time: data.start_time,
            end_time: data.end_time,
          }
        });
        if (!existing) {
          try {
            const s = await prisma.slot.create({ data });
            created.push(s);
          } catch (err: any) {
            // Unique-violation race between concurrent generators: skip.
            if (err?.code !== 'P2002') throw err;
          }
        }
      }
    }

    WebSocketService.broadcast('slots', created);
    return created;
  }

  public static async bulkDeleteSlots(venueId: string, slotIds: string[], partnerId?: string) {
    if (partnerId) await ClientService.assertPartnerVenue(partnerId, venueId);
    if (!Array.isArray(slotIds) || slotIds.length === 0) {
      throw new ValidationError("No slots selected");
    }
    const res = await prisma.slot.deleteMany({
      where: {
        slot_id: { in: slotIds },
        venue_id: venueId,
        status: { not: 'booked' }
      }
    });
    WebSocketService.broadcast('slots', { action: 'delete', slotIds });
    return res;
  }

  public static async toggleSlotBlock(slotId: string, partnerId?: string) {
    const slot = partnerId
      ? await ClientService.assertPartnerSlotOwner(partnerId, slotId)
      : await prisma.slot.findUnique({ where: { slot_id: slotId } });
    if (!slot) throw new NotFoundError("Slot not found");
    // A booked slot backs a real booking: blocking must never destroy it.
    if (slot.status === 'booked') {
      throw new ConflictError("Booked slots cannot be blocked. Cancel the booking first.", "SLOT_BOOKED");
    }

    const newStatus = slot.status === 'blocked_by_partner' ? 'available' : 'blocked_by_partner';
    const updated = await prisma.slot.update({
      where: { slot_id: slotId },
      data: { status: newStatus }
    });

    WebSocketService.broadcast('slots', [updated]);
    return updated;
  }

  public static async getPartnerBookings(partnerId: string) {
    const bookings = await prisma.booking.findMany({
      where: {
        venue: {
          partner_id: partnerId
        }
      },
      include: {
        user: true,
        venue: true,
        slot: true
      },
      orderBy: { created_at: 'desc' }
    });
    // Cash-collection state per booking (success cash txn exists).
    const ids = bookings.map((b) => b.booking_id);
    const cashTxns = ids.length
      ? await prisma.transaction.findMany({
          where: { booking_id: { in: ids }, txn_type: 'cash', txn_status: 'success' },
          select: { booking_id: true }
        })
      : [];
    const collected = new Set(cashTxns.map((t) => t.booking_id));
    // Partner sees player contact card only — never credentials.
    return sanitizeBookingForResponse(
      bookings.map((b) => ({ ...b, cash_collected: collected.has(b.booking_id) }))
    );
  }

  public static async checkinBooking(bookingId: string, partnerId?: string) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: {
        user: true,
        venue: true
      }
    });
    if (!booking) throw new NotFoundError("Booking not found");
    if (partnerId && booking.venue.partner_id !== partnerId) {
      throw new ForbiddenError("You cannot check in bookings for another partner's venue");
    }

    const updated = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: 'CONFIRMED' }
    });

    // P2-9: persisted + deduped check-in notification.
    await notifyUser(
      booking.user_id, 'booking',
      "Checked In!",
      `You have checked in successfully at ${booking.venue.name}. Enjoy your game!`,
      `checked-in:${bookingId}`
    ).catch(() => undefined);

    WebSocketService.broadcast('bookings', toBookingEvent({ ...updated, venue_id: booking.venue_id, slot_id: (booking as any).slot_id }));
    WebSocketService.emitToUser(booking.user_id, 'checked_in', toBookingEvent({ ...updated, venue_id: booking.venue_id, slot_id: (booking as any).slot_id }, { includePrivate: true }));
    return { success: true, message: "Player checked in successfully", booking: sanitizeBookingForResponse({ ...updated, user: booking.user, venue: booking.venue }) };
  }

  /**
   * Partner records venue cash (pay-at-venue 70% share) collected in person.
   * Ownership-enforced, idempotent, and limited to live pay-at-venue bookings
   * with a positive venue_amount. Recorded as a `cash` success transaction.
   */
  public static async collectVenueCash(bookingId: string, partnerId?: string) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: {
        user: true,
        venue: true,
        slot: true
      }
    });
    if (!booking) throw new NotFoundError("Booking not found");
    if (partnerId && booking.venue.partner_id !== partnerId) {
      throw new ForbiddenError("You cannot collect cash for another partner's venue");
    }
    if (booking.payment_mode !== 'pay_at_venue') {
      throw new ConflictError("Cash collection applies only to pay-at-venue bookings", "ILLEGAL_STATUS_TRANSITION");
    }
    const cashDue = Number(booking.venue_amount || 0);
    if (!Number.isFinite(cashDue) || cashDue <= 0) {
      throw new ConflictError("No venue cash due on this booking", "ILLEGAL_STATUS_TRANSITION");
    }
    if (booking.status !== 'CONFIRMED' && booking.status !== 'COMPLETED') {
      throw new ConflictError(`Cash can only be collected for confirmed bookings (current: ${booking.status})`, "ILLEGAL_STATUS_TRANSITION");
    }

    const existing = await prisma.transaction.findFirst({
      where: { booking_id: bookingId, txn_type: 'cash', txn_status: 'success' }
    });
    if (existing) {
      return {
        alreadyCollected: true,
        message: "Venue cash already collected",
        booking: sanitizeBookingForResponse({ ...booking, cash_collected: true }),
        transaction: existing
      };
    }

    const transaction = await prisma.transaction.create({
      data: {
        booking_id: bookingId,
        razorpay_order_id: `cash_${bookingId}`,
        razorpay_payment_id: `cash_${Date.now()}`,
        txn_type: 'cash',
        txn_status: 'success',
        amount: cashDue
      }
    });

    await notifyUser(
      booking.user_id, 'booking',
      "Cash Payment Recorded",
      `Your venue payment of ₹${cashDue.toFixed(2)} at ${booking.venue.name} was recorded. Enjoy your game!`,
      `cash-collected:${bookingId}`
    ).catch(() => undefined);

    WebSocketService.broadcast('bookings', toBookingEvent({ ...booking, venue_id: booking.venue_id, slot_id: (booking as any).slot_id }));

    return {
      alreadyCollected: false,
      message: `₹${cashDue.toFixed(2)} cash collected`,
      booking: sanitizeBookingForResponse({ ...booking, cash_collected: true }),
      transaction
    };
  }

  public static async getPartnerDisputes(partnerId: string) {
    const disputes = await prisma.dispute.findMany({
      where: {
        booking: {
          venue: {
            partner_id: partnerId
          }
        }
      },
      include: {
        booking: {
          include: {
            user: true,
            venue: true
          }
        }
      },
      orderBy: { dispute_id: 'desc' }
    });
    return disputes.map((d: any) => ({ ...d, booking: sanitizeBookingForResponse(d.booking) }));
  }

  public static async createPartnerDispute(bookingId: string, details: string, partnerId?: string) {
    if (!details || !details.trim()) throw new ValidationError("Dispute details are required");
    if (partnerId) {
      const booking = await prisma.booking.findUnique({
        where: { booking_id: bookingId },
        include: { venue: true },
      });
      if (!booking) throw new NotFoundError("Booking not found");
      if (booking.venue.partner_id !== partnerId) {
        throw new ForbiddenError("You cannot raise disputes on another partner's bookings");
      }
    }
    return prisma.dispute.create({
      data: {
        booking_id: bookingId,
        raised_by: 'partner',
        details,
        status: 'open'
      }
    });
  }

  public static async getPartnerSettlements(partnerId: string) {
    return prisma.settlement.findMany({
      where: { partner_id: partnerId },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async getPartnerReviews(partnerId: string) {
    const reviews = await prisma.venueReview.findMany({
      where: {
        venue: {
          partner_id: partnerId
        }
      },
      include: {
        user: true,
        venue: true
      },
      orderBy: { review_id: 'desc' }
    });
    return reviews.map((r: any) => ({ ...r, user: toPublicUser(r.user) }));
  }

  public static async replyToReview(reviewId: string, reply: string, partnerId?: string) {
    if (!reply || !reply.trim()) throw new ValidationError("Reply text is required");
    const review = await prisma.venueReview.findUnique({
      where: { review_id: reviewId },
      include: { venue: true },
    });
    if (!review) throw new NotFoundError("Review not found");
    if (partnerId && review.venue.partner_id !== partnerId) {
      throw new ForbiddenError("You cannot reply to reviews for another partner's venue");
    }

    return prisma.venueReview.update({
      where: { review_id: reviewId },
      data: { reply }
    });
  }

  private static readonly KYC_DOCUMENT_TYPES = new Set([
    'gst_certificate',
    'pan_card',
    'ownership_proof',
    'cancelled_cheque',
    'bank_statement',
  ]);

  public static async submitPartnerKyc(partnerId: string, documentType: string, fileUrl: string, gstNumber?: string, panNumber?: string, aadhaarNumber?: string) {
    if (!documentType || !ClientService.KYC_DOCUMENT_TYPES.has(documentType)) {
      throw new ValidationError("Invalid document type");
    }
    // KYC files must be private refs issued by our upload endpoint
    // (private:<random-filename>). Arbitrary external URLs are rejected so
    // sensitive documents cannot be spoofed or linked off-platform.
    if (!fileUrl || !/^private:[A-Za-z0-9._-]+$/.test(fileUrl)) {
      throw new ValidationError("KYC document must be uploaded through the secure document upload first");
    }
    // Update partner's details first if provided
    if (documentType === 'gst_certificate' && gstNumber) {
      await prisma.partner.update({
        where: { partner_id: partnerId },
        data: { gst_number: gstNumber }
      });
    }
    if (documentType === 'pan_card' && panNumber) {
      await prisma.partner.update({
        where: { partner_id: partnerId },
        data: { pan_number: panNumber }
      });
    }
    if (documentType === 'ownership_proof' && aadhaarNumber) {
      await prisma.partner.update({
        where: { partner_id: partnerId },
        data: { aadhaar_number: aadhaarNumber }
      });
    }

    const existing = await prisma.partnerDocument.findFirst({
      where: { partner_id: partnerId, document_type: documentType }
    });

    if (existing) {
      return prisma.partnerDocument.update({
        where: { doc_id: existing.doc_id },
        data: { file_url: fileUrl, status: 'pending' }
      });
    }

    return prisma.partnerDocument.create({
      data: {
        partner_id: partnerId,
        document_type: documentType,
        file_url: fileUrl,
        status: 'pending'
      }
    });
  }

  public static async sendChatMessage(userId: string, recipientId: string, text: string, senderRole: 'user' | 'partner' | 'admin' = 'user') {
    if (!recipientId || !text || !text.trim()) throw new ValidationError("Recipient and message text are required");
    if (text.length > 2000) throw new ValidationError("Message is too long");
    if (recipientId === userId) throw new ValidationError("Cannot send a message to yourself");
    const msg = await prisma.chatMessage.create({
      data: {
        sender_id: userId,
        sender_role: senderRole,
        recipient_id: recipientId,
        text: text.trim()
      }
    });

    // Send FCM Notification asynchronously
    (async () => {
      try {
        // Find sender name
        let senderName = "Someone";
        const senderUser = await prisma.user.findUnique({ where: { user_id: userId } });
        if (senderUser) {
          senderName = senderUser.name || "Athlete User";
        } else {
          const senderPartner = await prisma.partner.findUnique({ where: { partner_id: userId } });
          if (senderPartner) {
            senderName = "Venue Partner";
          }
        }

        // Find recipient FCM token
        let recipientToken: string | null = null;
        const recipientUser = await prisma.user.findUnique({ where: { user_id: recipientId } });
        if (recipientUser) {
          recipientToken = recipientUser.fcm_token;
        } else {
          const recipientPartner = await prisma.partner.findUnique({ where: { partner_id: recipientId } });
          if (recipientPartner) {
            recipientToken = recipientPartner.fcm_token;
          }
        }

        if (recipientToken) {
          const snippet = text.length > 50 ? `${text.substring(0, 47)}...` : text;
          await sendPushNotification(
            recipientToken,
            `New message from ${senderName}`,
            snippet
          );
        }
      } catch (err) {
        console.error("FCM error notifying recipient of new chat message:", err);
      }
    })();

    try {
      // Private message: deliver only to sender + recipient sockets.
      WebSocketService.emitToUser(msg.sender_id, 'chat_message', msg);
      WebSocketService.emitToUser(msg.recipient_id, 'chat_message', msg);
    } catch (_) { }
    return msg;
  }

  public static async reportProblem(userId: string, title: string, description: string) {
    return prisma.reportedProblem.create({
      data: {
        user_id: userId,
        title,
        description
      }
    });
  }

  public static async processRewardsAndMilestones(user: any, booking: any) {
    try {
      const settings = await AdminService.getSettings();
      
      const rewards = settings.rewardsConfig || {
        free_slot: { status: "Active", description: "Applies free booking slot coupon to next booking" },
        loyalty_points: { status: "Active", description: "Earn 10 points per ₹100 spend on online bookings", pointsPer100: 10 },
        cashback: { status: "Inactive", description: "10% cashback up to ₹100 inside user wallet", cashbackPercent: 10, maxCashback: 100 }
      };

      const milestones = settings.milestonesConfig || {
        first_booking: { count: 1, type: "Welcome", rewardType: "Free Slot", couponCode: "WELCOMEFREE" },
        bookings_5: { count: 5, type: "Loyalty", rewardType: "Cashback", cashbackAmount: 100 },
        bookings_10: { count: 10, type: "Power User", rewardType: "Coupon", couponCode: "SUPER20" },
        bookings_50: { count: 50, type: "Elite Athlete", rewardType: "Coupon", couponCode: "SUPER20" }
      };

      const spend = Number(booking.online_amount);
      let walletIncrement = 0;
      let pointsIncrement = 0;

      // Loyalty points & Cashback logic
      if (rewards.loyalty_points?.status === 'Active') {
        const rate = Number(rewards.loyalty_points.pointsPer100 || 10);
        pointsIncrement += Math.floor(spend / 100) * rate;
      }

      if (rewards.cashback?.status === 'Active') {
        const pct = Number(rewards.cashback.cashbackPercent || 10);
        const limit = Number(rewards.cashback.maxCashback || 100);
        let cashback = spend * (pct / 100);
        if (cashback > limit) cashback = limit;
        walletIncrement += cashback;
      }

      // Milestones checking
      const bookingCount = user.total_bookings;
      let achievedMilestoneType = "";
      let milestoneRewardType = "";
      let milestoneRewardValue = "";

      for (const [key, m] of Object.entries(milestones) as [string, any][]) {
        if (bookingCount === Number(m.count)) {
          achievedMilestoneType = m.type;
          milestoneRewardType = m.rewardType;
          milestoneRewardValue = m.couponCode || m.cashbackAmount || "";
          break;
        }
      }

      if (achievedMilestoneType) {
        let couponToLink: any = null;

        if (milestoneRewardType === 'Free Slot') {
          const code = `FREE_${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
          couponToLink = await prisma.coupon.create({
            data: {
              code,
              discount_type: 'percent',
              discount_value: 100,
              max_discount: null,
              min_order_value: 0,
              usage_limit: 1,
              is_active: true,
              valid_from: new Date(),
              valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
            }
          });
        } else if (milestoneRewardType === 'Cashback') {
          const cashbackAmount = Number(milestoneRewardValue || 100);
          walletIncrement += cashbackAmount;
          
          const code = `CBACK_${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
          couponToLink = await prisma.coupon.create({
            data: {
              code,
              discount_type: 'flat',
              discount_value: cashbackAmount,
              max_discount: cashbackAmount,
              min_order_value: 0,
              usage_limit: 1,
              is_active: true,
              valid_from: new Date(),
              valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
            }
          });
        } else if (milestoneRewardType === 'Coupon') {
          const code = String(milestoneRewardValue || 'SUPER20');
          let existing = await prisma.coupon.findUnique({ where: { code } });
          if (!existing) {
            existing = await prisma.coupon.create({
              data: {
                code,
                discount_type: 'percent',
                discount_value: 20,
                max_discount: 200,
                min_order_value: 200,
                usage_limit: 5,
                is_active: true,
                valid_from: new Date(),
                valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
              }
            });
          }
          couponToLink = existing;
        }

        if (couponToLink) {
          await prisma.userMilestone.create({
            data: {
              user_id: user.user_id,
              milestone_type: achievedMilestoneType,
              coupon_id: couponToLink.coupon_id
            }
          });
        }
      }

      if (walletIncrement > 0 || pointsIncrement > 0) {
        await prisma.user.update({
          where: { user_id: user.user_id },
          data: {
            wallet_balance: { increment: walletIncrement },
            reward_points: { increment: pointsIncrement }
          }
        });
      }

    } catch (err) {
      console.error("Error processing rewards/milestones:", err);
    }
  }

  public static async initiateWalletPayment(amount: number) {
    const topUp = Number(amount);
    if (!Number.isFinite(topUp) || topUp <= 0 || topUp > 100000) {
      throw new ValidationError("Invalid wallet top-up amount");
    }
    const { keyId, keySecret } = await resolveRazorpayKeys();
    let orderId = `order_wallet_mock_${Date.now()}_${randomInt(100000, 1000000)}`;

    if (keyId && keySecret) {
      try {
        const amountInPaise = toPaise(topUp);

        const response = await fetch('https://api.razorpay.com/v1/orders', {
          method: 'POST',
          headers: {
            'Authorization': `Basic ${razorpayBasicAuth(keyId, keySecret)}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            amount: amountInPaise,
            currency: RAZORPAY_CURRENCY,
            receipt: `wallet_${Date.now()}`
          })
        });

        const rzpOrder: any = await response.json();
        if (!rzpOrder || !rzpOrder.id || Number(rzpOrder.amount) !== amountInPaise) {
          throw new ValidationError("Payment gateway did not return a valid order. Please try again.");
        }
        orderId = rzpOrder.id;
      } catch (err: any) {
        if (err instanceof ValidationError) throw err;
        throw new ValidationError("Failed to create wallet payment order. Please try again.");
      }
    } else if (!isMockPaymentsAllowed()) {
      throw new ValidationError("Payment gateway is not configured. Please try again later.");
    }

    return { orderId, amount: topUp, currency: RAZORPAY_CURRENCY, key: keyId || undefined };
  }

  public static async verifyWalletPayment(
    userId: string,
    razorpayOrderId: string,
    razorpayPaymentId: string,
    amount: number,
    razorpaySignature?: string
  ) {
    if (!razorpayOrderId || !razorpayPaymentId) {
      throw new ValidationError("Order and payment identifiers are required");
    }
    const duplicate = await redis.get(`processed_wallet_payment:${razorpayPaymentId}`);
    if (duplicate) {
      throw new ConflictError("Payment already processed", "PAYMENT_REUSED");
    }

    const { keyId, keySecret } = await resolveRazorpayKeys();
    let finalAmount: number;

    if (isMockOrderId(razorpayOrderId) || isMockPaymentId(razorpayPaymentId)) {
      if (!isMockPaymentsAllowed()) {
        throw new ValidationError("Payment verification failed");
      }
      finalAmount = Number(amount);
      if (!Number.isFinite(finalAmount) || finalAmount <= 0 || finalAmount > 100000) {
        throw new ValidationError("Invalid wallet top-up amount");
      }
    } else {
      if (!keySecret) throw new ValidationError("Payment gateway is not configured");
      if (!razorpaySignature || !verifyRazorpayPaymentSignature(razorpayOrderId, razorpayPaymentId, razorpaySignature, keySecret)) {
        throw new ValidationError("Payment signature verification failed");
      }
      let paymentDetails: any;
      try {
        paymentDetails = await fetchRazorpayPayment(razorpayPaymentId, keyId, keySecret);
      } catch (_) {
        throw new ValidationError("Could not verify payment with the gateway. Please try again.");
      }
      if (!paymentDetails || paymentDetails.order_id !== razorpayOrderId) {
        throw new ValidationError("Payment is not linked to this order");
      }
      if (paymentDetails.status !== 'captured' && paymentDetails.status !== 'authorized') {
        throw new ValidationError("Payment is not successful");
      }
      if (String(paymentDetails.currency || '').toUpperCase() !== RAZORPAY_CURRENCY) {
        throw new ValidationError("Payment currency mismatch");
      }
      // Server truth: credit exactly what the gateway captured, never the
      // client-supplied amount.
      finalAmount = paiseToRupees(Number(paymentDetails.amount));
    }

    const claimed = await redis.set(`processed_wallet_payment:${razorpayPaymentId}`, userId, { NX: true, EX: 86400 * 30 });
    if (claimed === null) {
      throw new ConflictError("Payment already processed", "PAYMENT_REUSED");
    }

    const updatedUser = await prisma.user.update({
      where: { user_id: userId },
      data: {
        wallet_balance: { increment: finalAmount }
      }
    });

    return updatedUser;
  }
}
