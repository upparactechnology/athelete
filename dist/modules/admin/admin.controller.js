import { AdminService } from './admin.service.js';
import { sendSuccess } from '../../shared/utils/response.js';
import { ValidationError } from '../../shared/utils/errors.js';
export class AdminController {
    // 1. Admin Login
    static async login(req, res, next) {
        try {
            const { email, password } = req.body;
            if (!email || !password) {
                throw new ValidationError("Email and password are required");
            }
            const tokens = await AdminService.login(email, password);
            return sendSuccess(res, tokens);
        }
        catch (err) {
            next(err);
        }
    }
    // 2. Dashboard KPIs
    static async getDashboardStats(req, res, next) {
        try {
            const data = await AdminService.getDashboardStats();
            return sendSuccess(res, data);
        }
        catch (err) {
            next(err);
        }
    }
    // 3. Platform Users
    static async getUsers(req, res, next) {
        try {
            const users = await AdminService.getUsers();
            return sendSuccess(res, users);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateUserStatus(req, res, next) {
        try {
            const { id } = req.params;
            const { status } = req.body;
            if (!id || !status) {
                throw new ValidationError("User ID and status are required");
            }
            const user = await AdminService.updateUserStatus(id, status);
            return sendSuccess(res, user);
        }
        catch (err) {
            next(err);
        }
    }
    // 4. Platform Partners
    static async getPartners(req, res, next) {
        try {
            const partners = await AdminService.getPartners();
            return sendSuccess(res, partners);
        }
        catch (err) {
            next(err);
        }
    }
    // 5. KYC Document Queue
    static async getPendingKycDocuments(req, res, next) {
        try {
            const docs = await AdminService.getPendingKycDocuments();
            return sendSuccess(res, docs);
        }
        catch (err) {
            next(err);
        }
    }
    // 6. Review KYC Document
    static async updateKycDocumentStatus(req, res, next) {
        try {
            const { id } = req.params;
            const { status, rejection_note } = req.body;
            if (!id || !status) {
                throw new ValidationError("Document ID and status are required");
            }
            const doc = await AdminService.updateKycDocumentStatus(id, status, rejection_note);
            return sendSuccess(res, doc);
        }
        catch (err) {
            next(err);
        }
    }
    // 7. Venue Management
    static async getAllVenues(req, res, next) {
        try {
            const venues = await AdminService.getAllVenues();
            return sendSuccess(res, venues);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateVenueStatus(req, res, next) {
        try {
            const { id } = req.params;
            const { status } = req.body;
            if (!id || !status) {
                throw new ValidationError("Venue ID and status are required");
            }
            const venue = await AdminService.updateVenueStatus(id, status);
            return sendSuccess(res, venue);
        }
        catch (err) {
            next(err);
        }
    }
    static async toggleVenueFeatured(req, res, next) {
        try {
            const { id } = req.params;
            const { isFeatured } = req.body;
            if (!id || isFeatured === undefined) {
                throw new ValidationError("Venue ID and isFeatured boolean are required");
            }
            const data = await AdminService.toggleVenueFeatured(id, isFeatured);
            return sendSuccess(res, data);
        }
        catch (err) {
            next(err);
        }
    }
    // 8. Bookings Ledger
    static async getAllBookings(req, res, next) {
        try {
            const bookings = await AdminService.getAllBookings();
            return sendSuccess(res, bookings);
        }
        catch (err) {
            next(err);
        }
    }
    static async cancelBooking(req, res, next) {
        try {
            const { id } = req.params;
            if (!id)
                throw new ValidationError("Booking ID is required");
            const booking = await AdminService.cancelBooking(id);
            return sendSuccess(res, booking);
        }
        catch (err) {
            next(err);
        }
    }
    static async reassignBookingSlot(req, res, next) {
        try {
            const { id } = req.params;
            const { newSlotId } = req.body;
            if (!id || !newSlotId) {
                throw new ValidationError("Booking ID and newSlotId are required");
            }
            const booking = await AdminService.reassignBookingSlot(id, newSlotId);
            return sendSuccess(res, booking);
        }
        catch (err) {
            next(err);
        }
    }
    // 9. Finance Transactions
    static async getTransactions(req, res, next) {
        try {
            const transactions = await AdminService.getTransactions();
            return sendSuccess(res, transactions);
        }
        catch (err) {
            next(err);
        }
    }
    // 10. Coupon Codes
    static async getCoupons(req, res, next) {
        try {
            const coupons = await AdminService.getCoupons();
            return sendSuccess(res, coupons);
        }
        catch (err) {
            next(err);
        }
    }
    static async createCoupon(req, res, next) {
        try {
            const coupon = await AdminService.createCoupon(req.body);
            return sendSuccess(res, coupon, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateCoupon(req, res, next) {
        try {
            const { id } = req.params;
            if (!id)
                throw new ValidationError("Coupon ID is required");
            const coupon = await AdminService.updateCoupon(id, req.body);
            return sendSuccess(res, coupon);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteCoupon(req, res, next) {
        try {
            const { id } = req.params;
            if (!id)
                throw new ValidationError("Coupon ID is required");
            await AdminService.deleteCoupon(id);
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // 11. Disputes
    static async getDisputes(req, res, next) {
        try {
            const disputes = await AdminService.getDisputes();
            return sendSuccess(res, disputes);
        }
        catch (err) {
            next(err);
        }
    }
    static async resolveDispute(req, res, next) {
        try {
            const { id } = req.params;
            const { resolution } = req.body;
            if (!id || !resolution) {
                throw new ValidationError("Dispute ID and resolution are required");
            }
            const dispute = await AdminService.resolveDispute(id, resolution);
            return sendSuccess(res, dispute);
        }
        catch (err) {
            next(err);
        }
    }
    // 12. Broadcaster
    static async broadcastNotification(req, res, next) {
        try {
            const { audience_type, title, body } = req.body;
            if (!audience_type || !title || !body) {
                throw new ValidationError("audience_type, title, and body are required");
            }
            const broadcast = await AdminService.broadcastNotification(audience_type, title, body);
            return sendSuccess(res, broadcast);
        }
        catch (err) {
            next(err);
        }
    }
    static async getBroadcasts(req, res, next) {
        try {
            const broadcasts = await AdminService.getBroadcasts();
            return sendSuccess(res, broadcasts);
        }
        catch (err) {
            next(err);
        }
    }
    // 13. Slots & Tags
    static async getVenueSlots(req, res, next) {
        try {
            const { venueId } = req.params;
            if (!venueId)
                throw new ValidationError("Venue ID is required");
            const slots = await AdminService.getVenueSlots(venueId);
            return sendSuccess(res, slots);
        }
        catch (err) {
            next(err);
        }
    }
    static async applyDemandTag(req, res, next) {
        try {
            const { slotIds, tag } = req.body;
            if (!slotIds || !Array.isArray(slotIds) || !tag) {
                throw new ValidationError("slotIds array and tag string are required");
            }
            const slots = await AdminService.applyDemandTag(slotIds, tag);
            return sendSuccess(res, slots);
        }
        catch (err) {
            next(err);
        }
    }
    static async removeDemandTag(req, res, next) {
        try {
            const { slotIds } = req.body;
            if (!slotIds || !Array.isArray(slotIds)) {
                throw new ValidationError("slotIds array is required");
            }
            const slots = await AdminService.removeDemandTag(slotIds);
            return sendSuccess(res, slots);
        }
        catch (err) {
            next(err);
        }
    }
    // ==========================================
    // COMPLETE CRUD CONTROLLERS
    // ==========================================
    // Users CRUD
    static async createUser(req, res, next) {
        try {
            const user = await AdminService.createUser(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create User", user.user_id, "SUCCESS");
            return sendSuccess(res, user, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateUser(req, res, next) {
        try {
            const { id } = req.params;
            const user = await AdminService.updateUser(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update User", id, "SUCCESS");
            return sendSuccess(res, user);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteUser(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteUser(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete User", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Partners CRUD
    static async createPartner(req, res, next) {
        try {
            const partner = await AdminService.createPartner(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Partner", partner.partner_id, "SUCCESS");
            return sendSuccess(res, partner, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updatePartner(req, res, next) {
        try {
            const { id } = req.params;
            const partner = await AdminService.updatePartner(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Partner", id, "SUCCESS");
            return sendSuccess(res, partner);
        }
        catch (err) {
            next(err);
        }
    }
    static async deletePartner(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deletePartner(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Partner", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Venues CRUD
    static async createVenue(req, res, next) {
        try {
            const venue = await AdminService.createVenue(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Venue", venue.venue_id, "SUCCESS");
            return sendSuccess(res, venue, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateVenue(req, res, next) {
        try {
            const { id } = req.params;
            const venue = await AdminService.updateVenue(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Venue", id, "SUCCESS");
            return sendSuccess(res, venue);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteVenue(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteVenue(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Venue", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Bookings CRUD
    static async createBooking(req, res, next) {
        try {
            const booking = await AdminService.createBooking(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Booking", booking.booking_id, "SUCCESS");
            return sendSuccess(res, booking, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateBooking(req, res, next) {
        try {
            const { id } = req.params;
            const booking = await AdminService.updateBooking(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Booking", id, "SUCCESS");
            return sendSuccess(res, booking);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteBooking(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteBooking(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Booking", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Tournaments CRUD
    static async getTournaments(req, res, next) {
        try {
            const tournaments = await AdminService.getTournaments();
            return sendSuccess(res, tournaments);
        }
        catch (err) {
            next(err);
        }
    }
    static async createTournament(req, res, next) {
        try {
            const tournament = await AdminService.createTournament(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Tournament", tournament.tournament_id, "SUCCESS");
            return sendSuccess(res, tournament, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateTournament(req, res, next) {
        try {
            const { id } = req.params;
            const tournament = await AdminService.updateTournament(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Tournament", id, "SUCCESS");
            return sendSuccess(res, tournament);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteTournament(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteTournament(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Tournament", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Reviews CRUD
    static async getReviews(req, res, next) {
        try {
            const reviews = await AdminService.getReviews();
            return sendSuccess(res, reviews);
        }
        catch (err) {
            next(err);
        }
    }
    static async createReview(req, res, next) {
        try {
            const review = await AdminService.createReview(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Review", review.review_id, "SUCCESS");
            return sendSuccess(res, review, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateReview(req, res, next) {
        try {
            const { id } = req.params;
            const review = await AdminService.updateReview(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Review", id, "SUCCESS");
            return sendSuccess(res, review);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteReview(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteReview(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Review", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Settlements CRUD
    static async getSettlements(req, res, next) {
        try {
            const settlements = await AdminService.getSettlements();
            return sendSuccess(res, settlements);
        }
        catch (err) {
            next(err);
        }
    }
    static async createSettlement(req, res, next) {
        try {
            const settlement = await AdminService.createSettlement(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Settlement", settlement.settlement_id, "SUCCESS");
            return sendSuccess(res, settlement, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateSettlement(req, res, next) {
        try {
            const { id } = req.params;
            const settlement = await AdminService.updateSettlement(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Settlement", id, "SUCCESS");
            return sendSuccess(res, settlement);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteSettlement(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteSettlement(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Settlement", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Transactions CRUD
    static async createTransaction(req, res, next) {
        try {
            const txn = await AdminService.createTransaction(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Transaction", txn.txn_id, "SUCCESS");
            return sendSuccess(res, txn, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateTransaction(req, res, next) {
        try {
            const { id } = req.params;
            const txn = await AdminService.updateTransaction(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Transaction", id, "SUCCESS");
            return sendSuccess(res, txn);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteTransaction(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteTransaction(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Transaction", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Banners CRUD
    static async getBanners(req, res, next) {
        try {
            const banners = await AdminService.getBanners();
            return sendSuccess(res, banners);
        }
        catch (err) {
            next(err);
        }
    }
    static async createBanner(req, res, next) {
        try {
            const banner = await AdminService.createBanner(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Banner", banner.banner_id, "SUCCESS");
            return sendSuccess(res, banner, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateBanner(req, res, next) {
        try {
            const { id } = req.params;
            const banner = await AdminService.updateBanner(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Banner", id, "SUCCESS");
            return sendSuccess(res, banner);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteBanner(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteBanner(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Banner", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Disputes CRUD extension
    static async createDispute(req, res, next) {
        try {
            const dispute = await AdminService.createDispute(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Dispute", dispute.dispute_id, "SUCCESS");
            return sendSuccess(res, dispute, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteDispute(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteDispute(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Dispute", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Broadcasts CRUD extension
    static async deleteBroadcast(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteBroadcast(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Broadcast", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Audit Logs CRUD
    static async getAuditLogs(req, res, next) {
        try {
            const logs = await AdminService.getAuditLogs();
            return sendSuccess(res, logs);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteAuditLogs(req, res, next) {
        try {
            await AdminService.deleteAuditLogs();
            return sendSuccess(res, { cleared: true });
        }
        catch (err) {
            next(err);
        }
    }
    // Settings CRUD
    static async getSettings(req, res, next) {
        try {
            const settings = await AdminService.getSettings();
            return sendSuccess(res, settings);
        }
        catch (err) {
            next(err);
        }
    }
    static async saveSettings(req, res, next) {
        try {
            const settings = await AdminService.saveSettings(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update System Settings", "system", "SUCCESS");
            return sendSuccess(res, settings);
        }
        catch (err) {
            next(err);
        }
    }
    // Roles CRUD
    static async getRoles(req, res, next) {
        try {
            const roles = await AdminService.getRoles();
            return sendSuccess(res, roles);
        }
        catch (err) {
            next(err);
        }
    }
    static async createRole(req, res, next) {
        try {
            const role = await AdminService.createRole(req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Create Role Profile", role.id, "SUCCESS");
            return sendSuccess(res, role, 201);
        }
        catch (err) {
            next(err);
        }
    }
    static async updateRole(req, res, next) {
        try {
            const { id } = req.params;
            const role = await AdminService.updateRole(id, req.body);
            await AdminService.addAuditLog(req.user?.id || "admin", "Update Role Profile", id, "SUCCESS");
            return sendSuccess(res, role);
        }
        catch (err) {
            next(err);
        }
    }
    static async deleteRole(req, res, next) {
        try {
            const { id } = req.params;
            await AdminService.deleteRole(id);
            await AdminService.addAuditLog(req.user?.id || "admin", "Delete Role Profile", id, "SUCCESS");
            return sendSuccess(res, { deleted: true });
        }
        catch (err) {
            next(err);
        }
    }
}
export default AdminController;
