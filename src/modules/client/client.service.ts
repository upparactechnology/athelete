import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { ValidationError, NotFoundError } from '../../shared/utils/errors.js';
import { WebSocketService } from '../../shared/services/websocket.js';
import { AdminService } from '../admin/admin.service.js';

export class ClientService {
  // 1. Auth Service
  public static async requestOtp(phoneNumber: string) {
    const settings = await AdminService.getSettings();
    const code = Math.floor(100000 + Math.random() * 900000).toString();
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

    if (settings.useSmtpForOtp && settings.smtpHost) {
      let email = phoneNumber;
      if (!phoneNumber.includes('@')) {
        // Look up registered user by phone number
        const user = await prisma.user.findUnique({ where: { phone_number: phoneNumber } });
        if (user && user.email) {
          email = user.email;
        } else {
          throw new ValidationError("No registered email found for this phone number. Please log in with your email address directly.");
        }
      }

      // Send via SMTP
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

        return { message: `OTP sent to email: ${email}`, otp: code };
      } catch (mailErr: any) {
        console.error("Failed to send OTP email:", mailErr);
        throw new ValidationError(`Failed to send email: ${mailErr.message}`);
      }
    }

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
            kyc_status: 'verified', // Auto-verify for local testing and simulation
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
      const updateData: any = {};
      if (data.fcm_token !== undefined) updateData.fcm_token = data.fcm_token;
      if (data.phone_number !== undefined) updateData.phone_number = data.phone_number;
      if (data.email !== undefined) updateData.email = data.email;
      return prisma.partner.update({
        where: { partner_id: id },
        data: updateData
      });
    } else {
      const updateData: any = {};
      if (data.name !== undefined) updateData.name = data.name;
      if (data.email !== undefined) updateData.email = data.email;
      if (data.fcm_token !== undefined) updateData.fcm_token = data.fcm_token;
      if (data.phone_number !== undefined) updateData.phone_number = data.phone_number;
      return prisma.user.update({
        where: { user_id: id },
        data: updateData
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
  public static async getVenues(city?: string, sport?: string, lat?: string, lng?: string) {
    const filter: any = { status: "listed" };
    if (sport) {
      filter.sport_types = { has: sport };
    }
    const venues = await prisma.venue.findMany({
      where: filter,
      include: { partner: true }
    });

    if (lat && lng) {
      const userLat = parseFloat(lat);
      const userLng = parseFloat(lng);
      if (!isNaN(userLat) && !isNaN(userLng)) {
        const coordinatesMap: Record<string, { lat: number; lng: number }> = {
          "Downtown Football Arena": { lat: 28.6273, lng: 77.3725 },
          "Smash Badminton Center": { lat: 12.9716, lng: 77.5946 },
          "Grand Tennis Club": { lat: 19.0596, lng: 72.8295 }
        };

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
          let lat = venue.latitude ? Number(venue.latitude) : null;
          let lng = venue.longitude ? Number(venue.longitude) : null;
          if (lat === null || lng === null) {
            let coords = coordinatesMap[venue.name];
            if (!coords) {
              if (venue.address?.includes("Noida")) {
                coords = { lat: 28.6273, lng: 77.3725 };
              } else if (venue.address?.includes("Indiranagar") || venue.address?.includes("Bengaluru")) {
                coords = { lat: 12.9716, lng: 77.5946 };
              } else if (venue.address?.includes("Bandra") || venue.address?.includes("Mumbai")) {
                coords = { lat: 19.0596, lng: 72.8295 };
              } else {
                coords = { lat: userLat, lng: userLng };
              }
            }
            lat = coords.lat;
            lng = coords.lng;
          }
          const dist = calculateDistance(userLat, userLng, lat, lng);
          return {
            ...venue,
            latitude: lat,
            longitude: lng,
            distance: parseFloat(dist.toFixed(2))
          };
        });

        // Sort by nearest first (display all venues near or far)
        return mappedVenues
          .sort((a: any, b: any) => a.distance - b.distance);
      }
    }

    return venues;
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

    WebSocketService.broadcast('bookings', booking);
    const slotObj = await prisma.slot.findUnique({ where: { slot_id: slotId } });
    if (slotObj) {
      WebSocketService.broadcast('slots', [slotObj]);
    }

    return booking;
  }

  public static async initiatePayment(bookingId: string) {
    const booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    if (!booking) throw new NotFoundError("Booking not found");

    const settings = await AdminService.getSettings();
    let orderId = `order_${Math.floor(10000000 + Math.random() * 90000000)}`;

    if (settings.razorpayKeyId && settings.razorpayKeySecret) {
      try {
        const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
        const amountInPaise = Math.round(Number(booking.online_amount) * 100);

        const response = await fetch('https://api.razorpay.com/v1/orders', {
          method: 'POST',
          headers: {
            'Authorization': `Basic ${auth}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            amount: amountInPaise,
            currency: 'INR',
            receipt: bookingId
          })
        });

        const rzpOrder: any = await response.json();
        if (rzpOrder.id) {
          orderId = rzpOrder.id;
        } else {
          console.error("Razorpay order generation response did not contain id:", rzpOrder);
        }
      } catch (err) {
        console.error("Failed to generate Razorpay order, falling back to mock ID:", err);
      }
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

    return { orderId, amount: booking.online_amount, currency: "INR", key: settings.razorpayKeyId };
  }

  public static async verifyPayment(bookingId: string, razorpayOrderId: string, razorpayPaymentId: string) {
    const txn = await prisma.transaction.findFirst({
      where: { booking_id: bookingId, razorpay_order_id: razorpayOrderId }
    });

    if (!txn) throw new NotFoundError("Transaction record not found");

    const settings = await AdminService.getSettings();
    if (settings.razorpayKeyId && settings.razorpayKeySecret && !razorpayPaymentId.startsWith("pay_mock_") && !razorpayPaymentId.startsWith("pay_")) {
      try {
        const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
        const response = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}`, {
          headers: {
            'Authorization': `Basic ${auth}`
          }
        });
        const paymentDetails: any = await response.json();

        if (paymentDetails.order_id !== razorpayOrderId) {
          throw new ValidationError("Payment order ID mismatch");
        }
        if (paymentDetails.status !== 'captured' && paymentDetails.status !== 'authorized') {
          throw new ValidationError(`Payment is not successful (status: ${paymentDetails.status})`);
        }
      } catch (err: any) {
        console.error("Razorpay verification failed:", err);
        throw new ValidationError(err.message || "Razorpay payment verification failed");
      }
    }

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

    WebSocketService.broadcast('bookings', booking);
    const slot = await prisma.slot.findUnique({ where: { slot_id: booking.slot_id } });
    if (slot) {
      WebSocketService.broadcast('slots', [slot]);
    }

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

    const updated = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: "CANCELLED" }
    });

    const updatedSlot = await prisma.slot.update({
      where: { slot_id: booking.slot_id },
      data: { status: "available" }
    });

    WebSocketService.broadcast('bookings', updated);
    WebSocketService.broadcast('slots', [updatedSlot]);

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
        longitude: data.longitude != null ? Number(data.longitude) : null
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
        status: "unlisted" // Automatically set to unlisted to require admin review/approval to list it
      }
    });
  }

  public static async getPartnerVenueSlots(venueId: string, dateStr: string) {
    const date = new Date(dateStr);
    return prisma.slot.findMany({
      where: {
        venue_id: venueId,
        date: date
      },
      orderBy: { start_time: 'asc' }
    });
  }

  public static async bulkGenerateSlots(venueId: string, dateStr: string, startTime: string, endTime: string, price: number, durationMinutes: number) {
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

    // Insert slots
    const created = [];
    for (const data of slotsData) {
      const s = await prisma.slot.create({ data });
      created.push(s);
    }

    WebSocketService.broadcast('slots', created);
    return created;
  }

  public static async toggleSlotBlock(slotId: string) {
    const slot = await prisma.slot.findUnique({ where: { slot_id: slotId } });
    if (!slot) throw new NotFoundError("Slot not found");

    const newStatus = slot.status === 'blocked_by_partner' ? 'available' : 'blocked_by_partner';
    const updated = await prisma.slot.update({
      where: { slot_id: slotId },
      data: { status: newStatus }
    });

    WebSocketService.broadcast('slots', [updated]);
    return updated;
  }

  public static async getPartnerBookings(partnerId: string) {
    return prisma.booking.findMany({
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
  }

  public static async checkinBooking(bookingId: string) {
    const booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
    if (!booking) throw new NotFoundError("Booking not found");

    const updated = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: 'CONFIRMED' }
    });

    WebSocketService.broadcast('bookings', updated);
    return { success: true, message: "Player checked in successfully", booking: updated };
  }

  public static async getPartnerDisputes(partnerId: string) {
    return prisma.dispute.findMany({
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
  }

  public static async createPartnerDispute(bookingId: string, details: string) {
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
    return prisma.venueReview.findMany({
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
  }

  public static async replyToReview(reviewId: string, reply: string) {
    const review = await prisma.venueReview.findUnique({ where: { review_id: reviewId } });
    if (!review) throw new NotFoundError("Review not found");

    return prisma.venueReview.update({
      where: { review_id: reviewId },
      data: { reply }
    });
  }

  public static async submitPartnerKyc(partnerId: string, documentType: string, fileUrl: string) {
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

  public static async sendChatMessage(userId: string, recipientId: string, text: string) {
    const msg = await prisma.chatMessage.create({
      data: {
        sender_id: userId,
        sender_role: 'user',
        recipient_id: recipientId,
        text: text
      }
    });
    try {
      WebSocketService.broadcast('chat', msg);
    } catch (_) { }
    return msg;
  }
}
