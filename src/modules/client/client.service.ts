import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { ValidationError, NotFoundError } from '../../shared/utils/errors.js';

export class ClientService {
  // 1. Auth Service
  public static async requestOtp(phoneNumber: string) {
    const code = "123456"; // Standard test OTP
    const hash = bcrypt.hashSync(code, 10);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    await prisma.otpLog.create({
      data: {
        phone_number: phoneNumber,
        otp_hash: hash,
        expires_at: expiresAt,
        attempt_count: 0
      }
    });

    return { message: `Simulated SMS: OTP for ${phoneNumber} is ${code}`, otp: code };
  }

  public static async verifyOtp(phoneNumber: string, otp: string, role: string) {
    if (otp !== "123456") {
      const otpLog = await prisma.otpLog.findFirst({
        where: { phone_number: phoneNumber, expires_at: { gte: new Date() } },
        orderBy: { expires_at: 'desc' }
      });
      if (!otpLog || !bcrypt.compareSync(otp, otpLog.otp_hash)) {
        throw new ValidationError("Invalid or expired OTP");
      }
    }

    let id = "";
    let name = "";
    if (role === 'partner') {
      let partner = await prisma.partner.findUnique({ where: { phone_number: phoneNumber } });
      if (!partner) {
        partner = await prisma.partner.create({
          data: {
            phone_number: phoneNumber,
            kyc_status: 'verified', // Auto-verify for local testing and simulation
            total_earnings: 0.0
          }
        });
      }
      id = partner.partner_id;
      name = "Venue Partner";
    } else {
      let user = await prisma.user.findUnique({ where: { phone_number: phoneNumber } });
      if (!user) {
        user = await prisma.user.create({
          data: {
            phone_number: phoneNumber,
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

    const payload = { sub: id, role, status: "Active" };
    const accessToken = jwt.sign(payload, env.JWT_ACCESS_SECRET, { expiresIn: '1d' });
    const refreshToken = jwt.sign(payload, env.JWT_REFRESH_SECRET, { expiresIn: '7d' });

    // Store refresh token
    await prisma.refreshToken.create({
      data: {
        user_id: id,
        role,
        token_hash: bcrypt.hashSync(refreshToken, 10),
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      }
    });

    return {
      accessToken,
      refreshToken,
      user: {
        id,
        phone_number: phoneNumber,
        name,
        role
      }
    };
  }

  // 2. User/Partner Profiles
  public static async getProfile(id: string, role: string) {
    if (role === 'partner') {
      const partner = await prisma.partner.findUnique({
        where: { partner_id: id },
        include: { venues: true }
      });
      if (!partner) throw new NotFoundError("Partner profile not found");
      return partner;
    } else {
      const user = await prisma.user.findUnique({
        where: { user_id: id },
        include: { user_milestones: { include: { coupon: true } } }
      });
      if (!user) throw new NotFoundError("User profile not found");
      return user;
    }
  }

  public static async updateProfile(id: string, data: any, role: string) {
    if (role === 'partner') {
      return prisma.partner.update({
        where: { partner_id: id },
        data: { fcm_token: data.fcm_token }
      });
    } else {
      return prisma.user.update({
        where: { user_id: id },
        data: {
          name: data.name,
          email: data.email,
          fcm_token: data.fcm_token
        }
      });
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
  public static async getVenues(city?: string, sport?: string) {
    const filter: any = { status: "listed" };
    if (sport) {
      filter.sport_types = { has: sport };
    }
    return prisma.venue.findMany({
      where: filter,
      include: { partner: true }
    });
  }

  public static async getVenueDetails(venueId: string) {
    const venue = await prisma.venue.findUnique({
      where: { venue_id: venueId },
      include: {
        reviews: { include: { user: true } },
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
  public static async createBooking(userId: string, venueId: string, slotId: string, paymentMode: string, couponCode?: string) {
    const slot = await prisma.slot.findUnique({
      where: { slot_id: slotId },
      include: { venue: true }
    });

    if (!slot) throw new NotFoundError("Slot not found");
    if (slot.status !== 'available') throw new ValidationError("Slot is already booked or blocked");

    // Lock the slot immediately
    await prisma.slot.update({
      where: { slot_id: slotId },
      data: { status: 'booked' }
    });

    let discount = 0.0;
    if (couponCode) {
      const coupon = await prisma.coupon.findUnique({ where: { code: couponCode } });
      if (coupon && coupon.is_active && new Date(coupon.valid_until) >= new Date()) {
        if (coupon.discount_type === 'percent') {
          discount = (Number(slot.price) * Number(coupon.discount_value)) / 100;
          if (coupon.max_discount) {
            discount = Math.min(discount, Number(coupon.max_discount));
          }
        } else {
          discount = Number(coupon.discount_value);
        }
      }
    }

    const price = Number(slot.price);
    const bookingPrice = Math.max(0, price - discount);

    // Platform revenue calculations
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

    const eticketCode = `APV-2026-${Math.floor(100000 + Math.random() * 900000)}`;

    const booking = await prisma.booking.create({
      data: {
        user_id: userId,
        venue_id: venueId,
        slot_id: slotId,
        status: paymentMode === 'free' ? 'CONFIRMED' : 'PENDING',
        payment_mode: paymentMode,
        eticket_code: eticketCode,
        convenience_fee: convenienceFee,
        commission_amount: commissionAmount,
        gst_amount: gstAmount,
        partner_amount: partnerAmount,
        online_amount: onlineAmount,
        venue_amount: venueAmount
      }
    });

    return booking;
  }

  public static async initiatePayment(bookingId: string) {
    const booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    if (!booking) throw new NotFoundError("Booking not found");

    const orderId = `order_${Math.floor(10000000 + Math.random() * 90000000)}`;
    await prisma.transaction.create({
      data: {
        booking_id: bookingId,
        razorpay_order_id: orderId,
        txn_type: "capture",
        txn_status: "pending",
        amount: booking.online_amount
      }
    });

    return { orderId, amount: booking.online_amount, currency: "INR" };
  }

  public static async verifyPayment(bookingId: string, razorpayOrderId: string, razorpayPaymentId: string) {
    const txn = await prisma.transaction.findFirst({
      where: { booking_id: bookingId, razorpay_order_id: razorpayOrderId }
    });

    if (!txn) throw new NotFoundError("Transaction record not found");

    await prisma.transaction.update({
      where: { txn_id: txn.txn_id },
      data: {
        razorpay_payment_id: razorpayPaymentId,
        txn_status: "success"
      }
    });

    const booking = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: "CONFIRMED" }
    });

    // Update user stats
    await prisma.user.update({
      where: { user_id: booking.user_id },
      data: {
        total_bookings: { increment: 1 },
        total_spend: { increment: booking.online_amount }
      }
    });

    return booking;
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

  public static async cancelBooking(bookingId: string, userId: string) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: { slot: true }
    });

    if (!booking) throw new NotFoundError("Booking not found");
    if (booking.user_id !== userId) throw new ValidationError("Unauthorized cancellation");

    await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: "CANCELLED" }
    });

    await prisma.slot.update({
      where: { slot_id: booking.slot_id },
      data: { status: "available" }
    });

    return { message: "Booking cancelled successfully" };
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
    const tournament = await prisma.tournament.findUnique({ where: { tournament_id: tournamentId } });
    if (!tournament) throw new NotFoundError("Tournament not found");

    return prisma.tournamentRegistration.create({
      data: {
        tournament_id: tournamentId,
        user_id: userId,
        team_name: teamName,
        payment_status: "paid"
      }
    });
  }

  // 8. Notifications
  public static async getNotifications(recipientId: string, role: string) {
    return prisma.userNotification.findMany({
      where: { recipient_id: recipientId, recipient_type: role },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async readNotification(notifId: string) {
    return prisma.userNotification.update({
      where: { notif_id: notifId },
      data: { is_read: true }
    });
  }

  // 9. Content Banners
  public static async getBanners(target: string) {
    return prisma.banner.findMany({
      where: { target_app: { in: [target, 'all'] }, is_active: true },
      orderBy: { display_order: 'asc' }
    });
  }
}
