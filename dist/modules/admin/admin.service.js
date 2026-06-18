import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../../config/prisma.js';
import { redis, RedisKeys } from '../../config/redis.js';
import { env } from '../../config/env.js';
import { ValidationError, NotFoundError, ConflictError } from '../../shared/utils/errors.js';
export class AdminService {
    // 1. Admin Authentication
    static async login(email, password) {
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
    static async getDashboardStats() {
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
    static async getUsers() {
        return prisma.user.findMany({
            orderBy: { created_at: 'desc' }
        });
    }
    static async updateUserStatus(userId, status) {
        const user = await prisma.user.findUnique({
            where: { user_id: userId }
        });
        if (!user)
            throw new ValidationError("User not found");
        return prisma.user.update({
            where: { user_id: userId },
            data: { status }
        });
    }
    // 4. Platform Partners Ledger
    static async getPartners() {
        return prisma.partner.findMany({
            include: {
                partner_documents: true,
                venues: true
            },
            orderBy: { created_at: 'desc' }
        });
    }
    // 5. KYC Pending Document Queue
    static async getPendingKycDocuments() {
        return prisma.partnerDocument.findMany({
            where: { status: "pending" },
            include: {
                partner: true
            }
        });
    }
    // 6. Approve or Reject KYC Document
    static async updateKycDocumentStatus(docId, status, rejectionNote) {
        const doc = await prisma.partnerDocument.findUnique({
            where: { doc_id: docId }
        });
        if (!doc)
            throw new NotFoundError("Document not found");
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
        }
        else if (allDocs.some(d => d.status === "pending")) {
            overallKycStatus = "pending";
        }
        await prisma.partner.update({
            where: { partner_id: doc.partner_id },
            data: { kyc_status: overallKycStatus }
        });
        return updatedDoc;
    }
    // 7. Venues Management
    static async getAllVenues() {
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
    static async updateVenueStatus(venueId, status) {
        const venue = await prisma.venue.findUnique({
            where: { venue_id: venueId }
        });
        if (!venue)
            throw new NotFoundError("Venue not found");
        return prisma.venue.update({
            where: { venue_id: venueId },
            data: { status }
        });
    }
    // Toggle Featured status
    static async toggleVenueFeatured(venueId, isFeatured) {
        const venue = await prisma.venue.findUnique({
            where: { venue_id: venueId }
        });
        if (!venue)
            throw new NotFoundError("Venue not found");
        if (isFeatured) {
            await redis.zAdd(RedisKeys.featuredVenues(), {
                score: Date.now(),
                value: venueId
            });
        }
        else {
            await redis.zRem(RedisKeys.featuredVenues(), venueId);
        }
        return { venueId, isFeatured };
    }
    // 8. Bookings Operations
    static async getAllBookings() {
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
    static async cancelBooking(bookingId) {
        const booking = await prisma.booking.findUnique({
            where: { booking_id: bookingId },
            include: { slot: true }
        });
        if (!booking)
            throw new NotFoundError("Booking not found");
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
    static async reassignBookingSlot(bookingId, newSlotId) {
        const booking = await prisma.booking.findUnique({
            where: { booking_id: bookingId },
            include: { slot: true }
        });
        if (!booking)
            throw new NotFoundError("Booking not found");
        const newSlot = await prisma.slot.findUnique({
            where: { slot_id: newSlotId }
        });
        if (!newSlot)
            throw new NotFoundError("Target slot not found");
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
    static async getTransactions() {
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
    static async getCoupons() {
        return prisma.coupon.findMany({
            orderBy: { valid_from: 'desc' }
        });
    }
    static async createCoupon(data) {
        const exists = await prisma.coupon.findUnique({
            where: { code: data.code }
        });
        if (exists)
            throw new ConflictError("Coupon code already exists");
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
    static async updateCoupon(couponId, data) {
        const coupon = await prisma.coupon.findUnique({
            where: { coupon_id: couponId }
        });
        if (!coupon)
            throw new NotFoundError("Coupon not found");
        const formatted = {};
        if (data.discount_value !== undefined)
            formatted.discount_value = data.discount_value;
        if (data.max_discount !== undefined)
            formatted.max_discount = data.max_discount;
        if (data.min_order_value !== undefined)
            formatted.min_order_value = data.min_order_value;
        if (data.usage_limit !== undefined)
            formatted.usage_limit = data.usage_limit;
        if (data.is_active !== undefined)
            formatted.is_active = data.is_active;
        if (data.valid_from !== undefined)
            formatted.valid_from = new Date(data.valid_from);
        if (data.valid_until !== undefined)
            formatted.valid_until = new Date(data.valid_until);
        return prisma.coupon.update({
            where: { coupon_id: couponId },
            data: formatted
        });
    }
    static async deleteCoupon(couponId) {
        const coupon = await prisma.coupon.findUnique({
            where: { coupon_id: couponId }
        });
        if (!coupon)
            throw new NotFoundError("Coupon not found");
        return prisma.coupon.delete({
            where: { coupon_id: couponId }
        });
    }
    // 11. Disputes Management
    static async getDisputes() {
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
    static async resolveDispute(disputeId, resolution) {
        const dispute = await prisma.dispute.findUnique({
            where: { dispute_id: disputeId },
            include: { booking: true }
        });
        if (!dispute)
            throw new NotFoundError("Dispute not found");
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
    static async broadcastNotification(audienceType, title, body) {
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
        if (audienceType === "all")
            targetRole = "both";
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
    static async getBroadcasts() {
        return prisma.notificationBroadcast.findMany({
            orderBy: { sent_at: 'desc' }
        });
    }
    // 13. Slots Demand Tags (Surge Pricing)
    static async applyDemandTag(slotIds, tag) {
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
    static async removeDemandTag(slotIds) {
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
    static async createUser(data) {
        const exists = await prisma.user.findUnique({ where: { phone_number: data.phone_number } });
        if (exists)
            throw new ConflictError("Phone number already exists");
        return prisma.user.create({ data });
    }
    static async updateUser(userId, data) {
        const user = await prisma.user.findUnique({ where: { user_id: userId } });
        if (!user)
            throw new ValidationError("User not found");
        return prisma.user.update({ where: { user_id: userId }, data });
    }
    static async deleteUser(userId) {
        const user = await prisma.user.findUnique({ where: { user_id: userId } });
        if (!user)
            throw new ValidationError("User not found");
        return prisma.user.delete({ where: { user_id: userId } });
    }
    // Partners CRUD
    static async createPartner(data) {
        const exists = await prisma.partner.findUnique({ where: { phone_number: data.phone_number } });
        if (exists)
            throw new ConflictError("Partner phone number already exists");
        return prisma.partner.create({ data });
    }
    static async updatePartner(partnerId, data) {
        const partner = await prisma.partner.findUnique({ where: { partner_id: partnerId } });
        if (!partner)
            throw new ValidationError("Partner not found");
        return prisma.partner.update({ where: { partner_id: partnerId }, data });
    }
    static async deletePartner(partnerId) {
        const partner = await prisma.partner.findUnique({ where: { partner_id: partnerId } });
        if (!partner)
            throw new ValidationError("Partner not found");
        return prisma.partner.delete({ where: { partner_id: partnerId } });
    }
    // Venues CRUD
    static async createVenue(data) {
        return prisma.venue.create({ data });
    }
    static async updateVenue(venueId, data) {
        const venue = await prisma.venue.findUnique({ where: { venue_id: venueId } });
        if (!venue)
            throw new ValidationError("Venue not found");
        return prisma.venue.update({ where: { venue_id: venueId }, data });
    }
    static async deleteVenue(venueId) {
        const venue = await prisma.venue.findUnique({ where: { venue_id: venueId } });
        if (!venue)
            throw new ValidationError("Venue not found");
        return prisma.venue.delete({ where: { venue_id: venueId } });
    }
    // Bookings CRUD
    static async createBooking(data) {
        const ticketCode = `APV-2026-${Math.random().toString(36).substr(2, 6).toUpperCase()}`;
        return prisma.booking.create({
            data: { ...data, eticket_code: ticketCode }
        });
    }
    static async updateBooking(bookingId, data) {
        return prisma.booking.update({ where: { booking_id: bookingId }, data });
    }
    static async deleteBooking(bookingId) {
        return prisma.booking.delete({ where: { booking_id: bookingId } });
    }
    // Tournaments CRUD
    static async getTournaments() {
        return prisma.tournament.findMany({
            include: { venue: true },
            orderBy: { name: 'asc' }
        });
    }
    static async createTournament(data) {
        return prisma.tournament.create({ data });
    }
    static async updateTournament(tournamentId, data) {
        return prisma.tournament.update({ where: { tournament_id: tournamentId }, data });
    }
    static async deleteTournament(tournamentId) {
        return prisma.tournament.delete({ where: { tournament_id: tournamentId } });
    }
    // Reviews CRUD
    static async getReviews() {
        return prisma.venueReview.findMany({
            include: { user: true, venue: true, booking: true },
            orderBy: { review_id: 'desc' }
        });
    }
    static async createReview(data) {
        return prisma.venueReview.create({ data });
    }
    static async updateReview(reviewId, data) {
        return prisma.venueReview.update({ where: { review_id: reviewId }, data });
    }
    static async deleteReview(reviewId) {
        return prisma.venueReview.delete({ where: { review_id: reviewId } });
    }
    // Settlements CRUD
    static async getSettlements() {
        return prisma.settlement.findMany({
            include: { partner: true },
            orderBy: { created_at: 'desc' }
        });
    }
    static async createSettlement(data) {
        return prisma.settlement.create({
            data: {
                ...data,
                period_start: new Date(data.period_start),
                period_end: new Date(data.period_end)
            }
        });
    }
    static async updateSettlement(settlementId, data) {
        const formatted = { ...data };
        if (data.period_start)
            formatted.period_start = new Date(data.period_start);
        if (data.period_end)
            formatted.period_end = new Date(data.period_end);
        return prisma.settlement.update({ where: { settlement_id: settlementId }, data: formatted });
    }
    static async deleteSettlement(settlementId) {
        return prisma.settlement.delete({ where: { settlement_id: settlementId } });
    }
    // Transactions CRUD
    static async createTransaction(data) {
        return prisma.transaction.create({ data });
    }
    static async updateTransaction(txnId, data) {
        return prisma.transaction.update({ where: { txn_id: txnId }, data });
    }
    static async deleteTransaction(txnId) {
        return prisma.transaction.delete({ where: { txn_id: txnId } });
    }
    // Banners CRUD
    static async getBanners() {
        return prisma.banner.findMany({ orderBy: { display_order: 'asc' } });
    }
    static async createBanner(data) {
        return prisma.banner.create({ data });
    }
    static async updateBanner(bannerId, data) {
        return prisma.banner.update({ where: { banner_id: bannerId }, data });
    }
    static async deleteBanner(bannerId) {
        return prisma.banner.delete({ where: { banner_id: bannerId } });
    }
    // Disputes CRUD extension
    static async createDispute(data) {
        return prisma.dispute.create({ data });
    }
    static async deleteDispute(disputeId) {
        return prisma.dispute.delete({ where: { dispute_id: disputeId } });
    }
    // Broadcasts CRUD extension
    static async deleteBroadcast(broadcastId) {
        return prisma.notificationBroadcast.delete({ where: { broadcast_id: broadcastId } });
    }
    // Audit Logs CRUD
    static async getAuditLogs() {
        const raw = await redis.lRange('audit_logs', 0, -1);
        return raw.map(r => JSON.parse(r));
    }
    static async deleteAuditLogs() {
        await redis.del('audit_logs');
        return { cleared: true };
    }
    static async addAuditLog(operator, action, resourceId, result) {
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
    static async getSettings() {
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
    static async saveSettings(settings) {
        await redis.set('system_settings', JSON.stringify(settings));
        return settings;
    }
    // Roles CRUD
    static async getRoles() {
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
    static async createRole(data) {
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
    static async updateRole(id, data) {
        const roles = await this.getRoles();
        const idx = roles.findIndex((r) => r.id === id);
        if (idx !== -1) {
            roles[idx] = { ...roles[idx], ...data };
            await redis.set('system_roles', JSON.stringify(roles));
            return roles[idx];
        }
        throw new ValidationError("Role not found");
    }
    static async deleteRole(id) {
        const roles = await this.getRoles();
        const filtered = roles.filter((r) => r.id !== id);
        await redis.set('system_roles', JSON.stringify(filtered));
        return { deleted: true };
    }
    static async getVenueSlots(venueId) {
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
