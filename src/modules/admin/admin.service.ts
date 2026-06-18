import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../../config/prisma.js';
import { redis, RedisKeys } from '../../config/redis.js';
import { env } from '../../config/env.js';
import {
  ValidationError,
  NotFoundError,
  ConflictError
} from '../../shared/utils/errors.js';

export class AdminService {
  // 1. Admin Authentication
  public static async login(email: string, password: string) {
    if (email !== env.ADMIN_EMAIL) {
      throw new ValidationError("Invalid admin email or password");
    }

    const isMatch = bcrypt.compareSync(password, env.ADMIN_PASSWORD_HASH);
    if (!isMatch) {
      throw new ValidationError("Invalid admin email or password");
    }

    const payload = {
      sub: "admin-id-default",
      role: "admin",
      status: "active"
    };

    const token = jwt.sign(payload, env.JWT_ACCESS_SECRET, { expiresIn: '15m' });
    const refreshToken = jwt.sign(payload, env.JWT_REFRESH_SECRET, { expiresIn: '7d' });

    // Store refresh token
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await prisma.refreshToken.create({
      data: {
        user_id: "00000000-0000-0000-0000-000000000000",
        role: "admin",
        token_hash: bcrypt.hashSync(refreshToken, 10),
        expires_at: expiresAt
      }
    });

    return { token, refreshToken };
  }

  // 2. Analytics Dashboard KPIs
  public static async getDashboardStats() {
    const userCount = await prisma.user.count();
    const partnerCount = await prisma.partner.count();
    const venueCount = await prisma.venue.count();
    const bookingCount = await prisma.booking.count();

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);

    const todayBookingsCount = await prisma.booking.count({
      where: {
        created_at: {
          gte: todayStart,
          lte: todayEnd
        }
      }
    });

    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);

    const monthlyBookings = await prisma.booking.findMany({
      where: {
        status: "CONFIRMED",
        created_at: {
          gte: monthStart
        }
      }
    });

    let monthlyRevenue = 0;
    for (const b of monthlyBookings) {
      monthlyRevenue += Number(b.online_amount) + Number(b.venue_amount);
    }

    const pendingKycCount = await prisma.partnerDocument.count({
      where: { status: "pending" }
    });

    const activeTournamentsCount = await prisma.tournament.count({
      where: {
        status: {
          in: ["upcoming", "open", "full"]
        }
      }
    });

    const pendingRefundsCount = await prisma.transaction.count({
      where: {
        txn_type: "refund",
        txn_status: "pending"
      }
    });

    // Outstanding PAV Amount
    const pavBookings = await prisma.booking.findMany({
      where: {
        payment_mode: "pay_at_venue",
        status: "CONFIRMED"
      }
    });
    let outstandingPavAmount = 0;
    for (const pb of pavBookings) {
      outstandingPavAmount += Number(pb.venue_amount);
    }

    const bookings = await prisma.booking.findMany({
      where: { status: "CONFIRMED" }
    });

    let totalRevenue = 0;
    let totalCommission = 0;

    for (const b of bookings) {
      totalRevenue += Number(b.online_amount) + Number(b.venue_amount);
      totalCommission += Number(b.commission_amount) + Number(b.gst_amount);
    }

    return {
      users: userCount,
      partners: partnerCount,
      venues: venueCount,
      bookings: bookingCount,
      totalRevenue,
      totalCommission,
      todayBookings: todayBookingsCount,
      monthlyRevenue,
      pendingKycApprovals: pendingKycCount,
      activeTournaments: activeTournamentsCount,
      pendingRefunds: pendingRefundsCount,
      outstandingPavAmount
    };
  }

  // 3. Platform Users Ledger
  public static async getUsers() {
    return prisma.user.findMany({
      orderBy: { created_at: 'desc' }
    });
  }

  public static async updateUserStatus(userId: string, status: string) {
    const user = await prisma.user.findUnique({
      where: { user_id: userId }
    });
    if (!user) throw new ValidationError("User not found");

    return prisma.user.update({
      where: { user_id: userId },
      data: { status }
    });
  }

  // 4. Platform Partners Ledger
  public static async getPartners() {
    return prisma.partner.findMany({
      include: {
        partner_documents: true,
        venues: true
      },
      orderBy: { created_at: 'desc' }
    });
  }

  // 5. KYC Pending Document Queue
  public static async getPendingKycDocuments() {
    return prisma.partnerDocument.findMany({
      where: { status: "pending" },
      include: {
        partner: true
      }
    });
  }

  // 6. Approve or Reject KYC Document
  public static async updateKycDocumentStatus(docId: string, status: string, rejectionNote?: string) {
    const doc = await prisma.partnerDocument.findUnique({
      where: { doc_id: docId }
    });

    if (!doc) throw new NotFoundError("Document not found");

    const updatedDoc = await prisma.partnerDocument.update({
      where: { doc_id: docId },
      data: {
        status,
        rejection_note: status === "rejected" ? rejectionNote : null
      }
    });

    // Check partner's other documents
    const allDocs = await prisma.partnerDocument.findMany({
      where: { partner_id: doc.partner_id }
    });

    let overallKycStatus = "verified";
    if (allDocs.some(d => d.status === "rejected")) {
      overallKycStatus = "rejected";
    } else if (allDocs.some(d => d.status === "pending")) {
      overallKycStatus = "pending";
    }

    await prisma.partner.update({
      where: { partner_id: doc.partner_id },
      data: { kyc_status: overallKycStatus }
    });

    return updatedDoc;
  }

  // 7. Venues Management
  public static async getAllVenues() {
    return prisma.venue.findMany({
      include: {
        partner: true,
        _count: {
          select: { bookings: true, slots: true }
        }
      },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async updateVenueStatus(venueId: string, status: string) {
    const venue = await prisma.venue.findUnique({
      where: { venue_id: venueId }
    });
    if (!venue) throw new NotFoundError("Venue not found");

    return prisma.venue.update({
      where: { venue_id: venueId },
      data: { status }
    });
  }

  // Toggle Featured status
  public static async toggleVenueFeatured(venueId: string, isFeatured: boolean) {
    const venue = await prisma.venue.findUnique({
      where: { venue_id: venueId }
    });
    if (!venue) throw new NotFoundError("Venue not found");

    if (isFeatured) {
      await redis.zAdd(RedisKeys.featuredVenues(), {
        score: Date.now(),
        value: venueId
      });
    } else {
      await redis.zRem(RedisKeys.featuredVenues(), venueId);
    }

    return { venueId, isFeatured };
  }

  // 8. Bookings Operations
  public static async getAllBookings() {
    return prisma.booking.findMany({
      include: {
        user: true,
        venue: true,
        slot: true,
        disputes: true
      },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async cancelBooking(bookingId: string) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: { slot: true }
    });

    if (!booking) throw new NotFoundError("Booking not found");
    if (booking.status === "CANCELLED") {
      throw new ConflictError("Booking is already cancelled");
    }

    const updated = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { status: "CANCELLED" }
    });

    // Make slot available
    await prisma.slot.update({
      where: { slot_id: booking.slot_id },
      data: { status: "available" }
    });

    // Log refund transaction
    await prisma.transaction.create({
      data: {
        booking_id: bookingId,
        razorpay_order_id: `REFUND-${booking.booking_id.substring(0, 8)}`,
        razorpay_payment_id: "REFUND_INTERNAL",
        txn_type: "refund",
        txn_status: "success",
        amount: booking.online_amount
      }
    });

    return updated;
  }

  public static async reassignBookingSlot(bookingId: string, newSlotId: string) {
    const booking = await prisma.booking.findUnique({
      where: { booking_id: bookingId },
      include: { slot: true }
    });

    if (!booking) throw new NotFoundError("Booking not found");

    const newSlot = await prisma.slot.findUnique({
      where: { slot_id: newSlotId }
    });

    if (!newSlot) throw new NotFoundError("Target slot not found");
    if (newSlot.status !== "available") {
      throw new ConflictError("Target slot is not available");
    }

    // Update booking's slot
    const updated = await prisma.booking.update({
      where: { booking_id: bookingId },
      data: { slot_id: newSlotId }
    });

    // Free old slot
    await prisma.slot.update({
      where: { slot_id: booking.slot_id },
      data: { status: "available" }
    });

    // Mark new slot booked
    await prisma.slot.update({
      where: { slot_id: newSlotId },
      data: { status: "booked" }
    });

    return updated;
  }

  // 9. Finance & Transactions
  public static async getTransactions() {
    return prisma.transaction.findMany({
      include: {
        booking: {
          include: {
            user: true,
            venue: true
          }
        }
      },
      orderBy: { created_at: 'desc' }
    });
  }

  // 10. Coupons Management
  public static async getCoupons() {
    return prisma.coupon.findMany({
      orderBy: { valid_from: 'desc' }
    });
  }

  public static async createCoupon(data: {
    code: string;
    discount_type: string;
    discount_value: number;
    max_discount?: number;
    min_order_value?: number;
    usage_limit: number;
    valid_from: string;
    valid_until: string;
  }) {
    const exists = await prisma.coupon.findUnique({
      where: { code: data.code }
    });
    if (exists) throw new ConflictError("Coupon code already exists");

    return prisma.coupon.create({
      data: {
        code: data.code.toUpperCase(),
        discount_type: data.discount_type,
        discount_value: data.discount_value,
        max_discount: data.max_discount || null,
        min_order_value: data.min_order_value || 0.0,
        usage_limit: data.usage_limit,
        valid_from: new Date(data.valid_from),
        valid_until: new Date(data.valid_until)
      }
    });
  }

  public static async updateCoupon(couponId: string, data: any) {
    const coupon = await prisma.coupon.findUnique({
      where: { coupon_id: couponId }
    });
    if (!coupon) throw new NotFoundError("Coupon not found");

    const formatted: any = {};
    if (data.discount_value !== undefined) formatted.discount_value = data.discount_value;
    if (data.max_discount !== undefined) formatted.max_discount = data.max_discount;
    if (data.min_order_value !== undefined) formatted.min_order_value = data.min_order_value;
    if (data.usage_limit !== undefined) formatted.usage_limit = data.usage_limit;
    if (data.is_active !== undefined) formatted.is_active = data.is_active;
    if (data.valid_from !== undefined) formatted.valid_from = new Date(data.valid_from);
    if (data.valid_until !== undefined) formatted.valid_until = new Date(data.valid_until);

    return prisma.coupon.update({
      where: { coupon_id: couponId },
      data: formatted
    });
  }

  public static async deleteCoupon(couponId: string) {
    const coupon = await prisma.coupon.findUnique({
      where: { coupon_id: couponId }
    });
    if (!coupon) throw new NotFoundError("Coupon not found");

    return prisma.coupon.delete({
      where: { coupon_id: couponId }
    });
  }

  // 11. Disputes Management
  public static async getDisputes() {
    return prisma.dispute.findMany({
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

  public static async resolveDispute(disputeId: string, resolution: string) {
    const dispute = await prisma.dispute.findUnique({
      where: { dispute_id: disputeId },
      include: { booking: true }
    });

    if (!dispute) throw new NotFoundError("Dispute not found");

    const updated = await prisma.dispute.update({
      where: { dispute_id: disputeId },
      data: {
        status: "resolved",
        resolution
      }
    });

    // If resolution is refund_user, cancel booking and trigger refund
    if (resolution === "refund_user" && dispute.booking.status !== "CANCELLED") {
      await this.cancelBooking(dispute.booking_id);
    }

    return updated;
  }

  // 12. FCM Broadcast Composer
  public static async broadcastNotification(audienceType: string, title: string, body: string) {
    const broadcast = await prisma.notificationBroadcast.create({
      data: {
        audience_type: audienceType,
        title,
        body,
        status: "sent"
      }
    });

    // In a real system, we would retrieve FCM tokens matching the audienceType and send FCM alerts.
    // For this prototype, we record the broadcast and add notifications to the in-app user inbox mock.
    let targetRole = audienceType.startsWith("all_partners") ? "partner" : "user";
    if (audienceType === "all") targetRole = "both";

    const users = await prisma.user.findMany();
    const partners = await prisma.partner.findMany();

    if (targetRole === "user" || targetRole === "both") {
      for (const u of users) {
        await prisma.userNotification.create({
          data: {
            recipient_id: u.user_id,
            recipient_type: "user",
            category: "alert",
            title,
            body
          }
        });
      }
    }

    if (targetRole === "partner" || targetRole === "both") {
      for (const p of partners) {
        await prisma.userNotification.create({
          data: {
            recipient_id: p.partner_id,
            recipient_type: "partner",
            category: "alert",
            title,
            body
          }
        });
      }
    }

    return broadcast;
  }

  public static async getBroadcasts() {
    return prisma.notificationBroadcast.findMany({
      orderBy: { sent_at: 'desc' }
    });
  }

  // 13. Slots Demand Tags (Surge Pricing)
  public static async applyDemandTag(slotIds: string[], tag: string) {
    const slots = await prisma.slot.findMany({
      where: { slot_id: { in: slotIds } },
      include: { venue: true }
    });

    const updatedSlots = [];
    for (const s of slots) {
      // Set price to 1.5x base price of venue if tag applied, else keep base price
      const basePrice = Number(s.venue.base_price);
      const surgedPrice = basePrice * 1.5;

      const updated = await prisma.slot.update({
        where: { slot_id: s.slot_id },
        data: {
          demand_tag: tag,
          price: surgedPrice
        }
      });
      updatedSlots.push(updated);
    }
    return updatedSlots;
  }

  public static async removeDemandTag(slotIds: string[]) {
    const slots = await prisma.slot.findMany({
      where: { slot_id: { in: slotIds } },
      include: { venue: true }
    });

    const updatedSlots = [];
    for (const s of slots) {
      const basePrice = Number(s.venue.base_price);

      const updated = await prisma.slot.update({
        where: { slot_id: s.slot_id },
        data: {
          demand_tag: null,
          price: basePrice
        }
      });
      updatedSlots.push(updated);
    }
    return updatedSlots;
  }

  // ==========================================
  // COMPLETE CRUD INTEGRATIONS
  // ==========================================

  // Users CRUD
  public static async createUser(data: { name: string; email: string; phone_number: string; status?: string }) {
    const exists = await prisma.user.findUnique({ where: { phone_number: data.phone_number } });
    if (exists) throw new ConflictError("Phone number already exists");
    return prisma.user.create({ data });
  }

  public static async updateUser(userId: string, data: { name?: string; email?: string; phone_number?: string; status?: string }) {
    const user = await prisma.user.findUnique({ where: { user_id: userId } });
    if (!user) throw new ValidationError("User not found");
    return prisma.user.update({ where: { user_id: userId }, data });
  }

  public static async deleteUser(userId: string) {
    const user = await prisma.user.findUnique({ where: { user_id: userId } });
    if (!user) throw new ValidationError("User not found");
    return prisma.user.delete({ where: { user_id: userId } });
  }

  // Partners CRUD
  public static async createPartner(data: { phone_number: string; kyc_status?: string; plan_tier?: string; total_earnings?: number }) {
    const exists = await prisma.partner.findUnique({ where: { phone_number: data.phone_number } });
    if (exists) throw new ConflictError("Partner phone number already exists");
    return prisma.partner.create({ data });
  }

  public static async updatePartner(partnerId: string, data: { phone_number?: string; kyc_status?: string; plan_tier?: string; total_earnings?: number }) {
    const partner = await prisma.partner.findUnique({ where: { partner_id: partnerId } });
    if (!partner) throw new ValidationError("Partner not found");
    return prisma.partner.update({ where: { partner_id: partnerId }, data });
  }

  public static async deletePartner(partnerId: string) {
    const partner = await prisma.partner.findUnique({ where: { partner_id: partnerId } });
    if (!partner) throw new ValidationError("Partner not found");
    return prisma.partner.delete({ where: { partner_id: partnerId } });
  }

  // Venues CRUD
  public static async createVenue(data: { partner_id: string; name: string; sport_types: string[]; base_price: number; status?: string }) {
    return prisma.venue.create({ data });
  }

  public static async updateVenue(venueId: string, data: { name?: string; sport_types?: string[]; base_price?: number; status?: string }) {
    const venue = await prisma.venue.findUnique({ where: { venue_id: venueId } });
    if (!venue) throw new ValidationError("Venue not found");
    return prisma.venue.update({ where: { venue_id: venueId }, data });
  }

  public static async deleteVenue(venueId: string) {
    const venue = await prisma.venue.findUnique({ where: { venue_id: venueId } });
    if (!venue) throw new ValidationError("Venue not found");
    return prisma.venue.delete({ where: { venue_id: venueId } });
  }

  // Bookings CRUD
  public static async createBooking(data: { user_id: string; venue_id: string; slot_id: string; payment_mode: string; convenience_fee: number; commission_amount: number; gst_amount: number; partner_amount: number; online_amount: number; venue_amount: number; status?: string }) {
    const ticketCode = `APV-2026-${Math.random().toString(36).substr(2, 6).toUpperCase()}`;
    return prisma.booking.create({
      data: { ...data, eticket_code: ticketCode }
    });
  }

  public static async updateBooking(bookingId: string, data: any) {
    return prisma.booking.update({ where: { booking_id: bookingId }, data });
  }

  public static async deleteBooking(bookingId: string) {
    return prisma.booking.delete({ where: { booking_id: bookingId } });
  }

  // Tournaments CRUD
  public static async getTournaments() {
    return prisma.tournament.findMany({
      include: { venue: true },
      orderBy: { name: 'asc' }
    });
  }

  public static async createTournament(data: { venue_id: string; name: string; sport_type: string; registration_fee: number; max_participants: number; status?: string }) {
    return prisma.tournament.create({ data });
  }

  public static async updateTournament(tournamentId: string, data: any) {
    return prisma.tournament.update({ where: { tournament_id: tournamentId }, data });
  }

  public static async deleteTournament(tournamentId: string) {
    return prisma.tournament.delete({ where: { tournament_id: tournamentId } });
  }

  // Reviews CRUD
  public static async getReviews() {
    return prisma.venueReview.findMany({
      include: { user: true, venue: true, booking: true },
      orderBy: { review_id: 'desc' }
    });
  }

  public static async createReview(data: { venue_id: string; user_id: string; booking_id: string; rating: number; comment: string; reply?: string }) {
    return prisma.venueReview.create({ data });
  }

  public static async updateReview(reviewId: string, data: { rating?: number; comment?: string; reply?: string }) {
    return prisma.venueReview.update({ where: { review_id: reviewId }, data });
  }

  public static async deleteReview(reviewId: string) {
    return prisma.venueReview.delete({ where: { review_id: reviewId } });
  }

  // Settlements CRUD
  public static async getSettlements() {
    return prisma.settlement.findMany({
      include: { partner: true },
      orderBy: { created_at: 'desc' }
    });
  }

  public static async createSettlement(data: { partner_id: string; period_start: string; period_end: string; gross_amount: number; platform_fee: number; net_amount: number; status?: string }) {
    return prisma.settlement.create({
      data: {
        ...data,
        period_start: new Date(data.period_start),
        period_end: new Date(data.period_end)
      }
    });
  }

  public static async updateSettlement(settlementId: string, data: any) {
    const formatted: any = { ...data };
    if (data.period_start) formatted.period_start = new Date(data.period_start);
    if (data.period_end) formatted.period_end = new Date(data.period_end);
    return prisma.settlement.update({ where: { settlement_id: settlementId }, data: formatted });
  }

  public static async deleteSettlement(settlementId: string) {
    return prisma.settlement.delete({ where: { settlement_id: settlementId } });
  }

  // Transactions CRUD
  public static async createTransaction(data: { booking_id: string; razorpay_order_id: string; razorpay_payment_id?: string; txn_type: string; txn_status: string; amount: number }) {
    return prisma.transaction.create({ data });
  }

  public static async updateTransaction(txnId: string, data: any) {
    return prisma.transaction.update({ where: { txn_id: txnId }, data });
  }

  public static async deleteTransaction(txnId: string) {
    return prisma.transaction.delete({ where: { txn_id: txnId } });
  }

  // Banners CRUD
  public static async getBanners() {
    return prisma.banner.findMany({ orderBy: { display_order: 'asc' } });
  }

  public static async createBanner(data: { title: string; image_url: string; link_url?: string; target_app: string; display_order: number; is_active?: boolean }) {
    return prisma.banner.create({ data });
  }

  public static async updateBanner(bannerId: string, data: any) {
    return prisma.banner.update({ where: { banner_id: bannerId }, data });
  }

  public static async deleteBanner(bannerId: string) {
    return prisma.banner.delete({ where: { banner_id: bannerId } });
  }

  // Disputes CRUD extension
  public static async createDispute(data: { booking_id: string; raised_by: string; details: string; status?: string }) {
    return prisma.dispute.create({ data });
  }

  public static async deleteDispute(disputeId: string) {
    return prisma.dispute.delete({ where: { dispute_id: disputeId } });
  }

  // Broadcasts CRUD extension
  public static async deleteBroadcast(broadcastId: string) {
    return prisma.notificationBroadcast.delete({ where: { broadcast_id: broadcastId } });
  }

  // Audit Logs CRUD
  public static async getAuditLogs() {
    const raw = await redis.lRange('audit_logs', 0, -1);
    return raw.map(r => JSON.parse(r));
  }

  public static async deleteAuditLogs() {
    await redis.del('audit_logs');
    return { cleared: true };
  }

  public static async addAuditLog(operator: string, action: string, resourceId: string, result: string) {
    const log = {
      time: new Date().toISOString(),
      operator,
      action,
      resourceId,
      result
    };
    await redis.lPush('audit_logs', JSON.stringify(log));
  }

  // Settings CRUD
  public static async getSettings() {
    const data = await redis.get('system_settings');
    if (!data) {
      return {
        platformName: "Athlete's POV",
        supportEmail: "support@athletepov.com",
        minWithdrawal: 1000,
        convenienceFee: 60
      };
    }
    return JSON.parse(data);
  }

  public static async saveSettings(settings: any) {
    await redis.set('system_settings', JSON.stringify(settings));
    return settings;
  }

  // Roles CRUD
  public static async getRoles() {
    const data = await redis.get('system_roles');
    if (!data) {
      const initial = [
        { id: '1', roleName: "Super Admin", description: "Full system configurations access", adminsCount: 1, permissions: "ALL_ACCESS" },
        { id: '2', roleName: "Finance Manager", description: "Access to Settlements, Transactions and Coupons", adminsCount: 0, permissions: "FINANCE_READ_WRITE" }
      ];
      await redis.set('system_roles', JSON.stringify(initial));
      return initial;
    }
    return JSON.parse(data);
  }

  public static async createRole(data: { roleName: string; description: string; permissions: string }) {
    const roles = await this.getRoles();
    const newRole = {
      id: Math.random().toString(36).substr(2, 9),
      roleName: data.roleName,
      description: data.description,
      adminsCount: 0,
      permissions: data.permissions
    };
    roles.push(newRole);
    await redis.set('system_roles', JSON.stringify(roles));
    return newRole;
  }

  public static async updateRole(id: string, data: any) {
    const roles = await this.getRoles();
    const idx = roles.findIndex((r: any) => r.id === id);
    if (idx !== -1) {
      roles[idx] = { ...roles[idx], ...data };
      await redis.set('system_roles', JSON.stringify(roles));
      return roles[idx];
    }
    throw new ValidationError("Role not found");
  }

  public static async deleteRole(id: string) {
    const roles = await this.getRoles();
    const filtered = roles.filter((r: any) => r.id !== id);
    await redis.set('system_roles', JSON.stringify(filtered));
    return { deleted: true };
  }

  public static async getVenueSlots(venueId: string) {
    return prisma.slot.findMany({
      where: { venue_id: venueId },
      orderBy: [
        { date: 'asc' },
        { start_time: 'asc' }
      ]
    });
  }
}
export default AdminService;
