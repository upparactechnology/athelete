import { Response, NextFunction } from 'express';
import { AuthRequest } from '../../shared/types/index.js';
import { AdminService } from './admin.service.js';
import { sendSuccess } from '../../shared/utils/response.js';
import { ValidationError } from '../../shared/utils/errors.js';

export class AdminController {
  // 1. Admin Login
  public static async login(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { email, password } = req.body;
      if (!email || !password) {
        throw new ValidationError("Email and password are required");
      }
      const tokens = await AdminService.login(email, password);
      return sendSuccess(res, tokens);
    } catch (err) {
      next(err);
    }
  }

  // 2. Dashboard KPIs
  public static async getDashboardStats(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const data = await AdminService.getDashboardStats();
      return sendSuccess(res, data);
    } catch (err) {
      next(err);
    }
  }

  // 3. Platform Users
  public static async getUsers(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const users = await AdminService.getUsers();
      return sendSuccess(res, users);
    } catch (err) {
      next(err);
    }
  }

  public static async updateUserStatus(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { status } = req.body;
      if (!id || !status) {
        throw new ValidationError("User ID and status are required");
      }
      const user = await AdminService.updateUserStatus(id, status);
      return sendSuccess(res, user);
    } catch (err) {
      next(err);
    }
  }

  // 4. Platform Partners
  public static async getPartners(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partners = await AdminService.getPartners();
      return sendSuccess(res, partners);
    } catch (err) {
      next(err);
    }
  }

  // 5. KYC Document Queue
  public static async getPendingKycDocuments(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const docs = await AdminService.getPendingKycDocuments();
      return sendSuccess(res, docs);
    } catch (err) {
      next(err);
    }
  }

  // 6. Review KYC Document
  public static async updateKycDocumentStatus(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { status, rejection_note } = req.body;
      if (!id || !status) {
        throw new ValidationError("Document ID and status are required");
      }
      const doc = await AdminService.updateKycDocumentStatus(id, status, rejection_note);
      return sendSuccess(res, doc);
    } catch (err) {
      next(err);
    }
  }

  // 7. Venue Management
  public static async getAllVenues(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const venues = await AdminService.getAllVenues();
      return sendSuccess(res, venues);
    } catch (err) {
      next(err);
    }
  }

  public static async updateVenueStatus(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { status } = req.body;
      if (!id || !status) {
        throw new ValidationError("Venue ID and status are required");
      }
      const venue = await AdminService.updateVenueStatus(id, status);
      return sendSuccess(res, venue);
    } catch (err) {
      next(err);
    }
  }

  public static async toggleVenueFeatured(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { isFeatured } = req.body;
      if (!id || isFeatured === undefined) {
        throw new ValidationError("Venue ID and isFeatured boolean are required");
      }
      const data = await AdminService.toggleVenueFeatured(id, isFeatured);
      return sendSuccess(res, data);
    } catch (err) {
      next(err);
    }
  }

  // 8. Bookings Ledger
  public static async getAllBookings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const bookings = await AdminService.getAllBookings();
      return sendSuccess(res, bookings);
    } catch (err) {
      next(err);
    }
  }

  public static async cancelBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      if (!id) throw new ValidationError("Booking ID is required");
      const booking = await AdminService.cancelBooking(id);
      return sendSuccess(res, booking);
    } catch (err) {
      next(err);
    }
  }

  public static async reassignBookingSlot(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { newSlotId } = req.body;
      if (!id || !newSlotId) {
        throw new ValidationError("Booking ID and newSlotId are required");
      }
      const booking = await AdminService.reassignBookingSlot(id, newSlotId);
      return sendSuccess(res, booking);
    } catch (err) {
      next(err);
    }
  }

  // 9. Finance Transactions
  public static async getTransactions(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const transactions = await AdminService.getTransactions();
      return sendSuccess(res, transactions);
    } catch (err) {
      next(err);
    }
  }

  // 10. Coupon Codes
  public static async getCoupons(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const coupons = await AdminService.getCoupons();
      return sendSuccess(res, coupons);
    } catch (err) {
      next(err);
    }
  }

  public static async createCoupon(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const coupon = await AdminService.createCoupon(req.body);
      return sendSuccess(res, coupon, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateCoupon(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      if (!id) throw new ValidationError("Coupon ID is required");
      const coupon = await AdminService.updateCoupon(id, req.body);
      return sendSuccess(res, coupon);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteCoupon(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      if (!id) throw new ValidationError("Coupon ID is required");
      await AdminService.deleteCoupon(id);
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // 11. Disputes
  public static async getDisputes(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const disputes = await AdminService.getDisputes();
      return sendSuccess(res, disputes);
    } catch (err) {
      next(err);
    }
  }

  public static async resolveDispute(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { resolution } = req.body;
      if (!id || !resolution) {
        throw new ValidationError("Dispute ID and resolution are required");
      }
      const dispute = await AdminService.resolveDispute(id, resolution);
      return sendSuccess(res, dispute);
    } catch (err) {
      next(err);
    }
  }

  // 12. Broadcaster
  public static async broadcastNotification(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { audience_type, title, body } = req.body;
      if (!audience_type || !title || !body) {
        throw new ValidationError("audience_type, title, and body are required");
      }
      const broadcast = await AdminService.broadcastNotification(audience_type, title, body);
      return sendSuccess(res, broadcast);
    } catch (err) {
      next(err);
    }
  }

  public static async getBroadcasts(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const broadcasts = await AdminService.getBroadcasts();
      return sendSuccess(res, broadcasts);
    } catch (err) {
      next(err);
    }
  }

  // 13. Slots & Tags
  public static async getVenueSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { venueId } = req.params;
      if (!venueId) throw new ValidationError("Venue ID is required");
      const slots = await AdminService.getVenueSlots(venueId);
      return sendSuccess(res, slots);
    } catch (err) {
      next(err);
    }
  }

  public static async applyDemandTag(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { slotIds, tag } = req.body;
      if (!slotIds || !Array.isArray(slotIds) || !tag) {
        throw new ValidationError("slotIds array and tag string are required");
      }
      const slots = await AdminService.applyDemandTag(slotIds, tag);
      return sendSuccess(res, slots);
    } catch (err) {
      next(err);
    }
  }

  public static async removeDemandTag(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { slotIds } = req.body;
      if (!slotIds || !Array.isArray(slotIds)) {
        throw new ValidationError("slotIds array is required");
      }
      const slots = await AdminService.removeDemandTag(slotIds);
      return sendSuccess(res, slots);
    } catch (err) {
      next(err);
    }
  }

  // ==========================================
  // COMPLETE CRUD CONTROLLERS
  // ==========================================

  // Users CRUD
  public static async createUser(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const user = await AdminService.createUser(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create User", user.user_id, "SUCCESS");
      return sendSuccess(res, user, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateUser(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const user = await AdminService.updateUser(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update User", id, "SUCCESS");
      return sendSuccess(res, user);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteUser(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteUser(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete User", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Partners CRUD
  public static async createPartner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partner = await AdminService.createPartner(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Partner", partner.partner_id, "SUCCESS");
      return sendSuccess(res, partner, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updatePartner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const partner = await AdminService.updatePartner(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Partner", id, "SUCCESS");
      return sendSuccess(res, partner);
    } catch (err) {
      next(err);
    }
  }

  public static async deletePartner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deletePartner(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Partner", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  public static async approveBankDetails(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const partner = await AdminService.approveBankDetails(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Approve Bank Details", id, "SUCCESS");
      return sendSuccess(res, partner);
    } catch (err) {
      next(err);
    }
  }

  public static async rejectBankDetails(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const partner = await AdminService.rejectBankDetails(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Reject Bank Details", id, "SUCCESS");
      return sendSuccess(res, partner);
    } catch (err) {
      next(err);
    }
  }

  // Venues CRUD
  public static async createVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const venue = await AdminService.createVenue(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Venue", venue.venue_id, "SUCCESS");
      return sendSuccess(res, venue, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const venue = await AdminService.updateVenue(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Venue", id, "SUCCESS");
      return sendSuccess(res, venue);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteVenue(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Venue", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Bookings CRUD
  public static async createBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const booking = await AdminService.createBooking(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Booking", booking.booking_id, "SUCCESS");
      return sendSuccess(res, booking, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const booking = await AdminService.updateBooking(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Booking", id, "SUCCESS");
      return sendSuccess(res, booking);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteBooking(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Booking", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Tournaments CRUD
  public static async getTournaments(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const tournaments = await AdminService.getTournaments();
      return sendSuccess(res, tournaments);
    } catch (err) {
      next(err);
    }
  }

  public static async createTournament(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const tournament = await AdminService.createTournament(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Tournament", tournament.tournament_id, "SUCCESS");
      return sendSuccess(res, tournament, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateTournament(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const tournament = await AdminService.updateTournament(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Tournament", id, "SUCCESS");
      return sendSuccess(res, tournament);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteTournament(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteTournament(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Tournament", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Reviews CRUD
  public static async getReviews(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const reviews = await AdminService.getReviews();
      return sendSuccess(res, reviews);
    } catch (err) {
      next(err);
    }
  }

  public static async createReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const review = await AdminService.createReview(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Review", review.review_id, "SUCCESS");
      return sendSuccess(res, review, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const review = await AdminService.updateReview(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Review", id, "SUCCESS");
      return sendSuccess(res, review);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteReview(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Review", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Settlements CRUD
  public static async getSettlements(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const settlements = await AdminService.getSettlements();
      return sendSuccess(res, settlements);
    } catch (err) {
      next(err);
    }
  }

  public static async createSettlement(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const settlement = await AdminService.createSettlement(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Settlement", settlement.settlement_id, "SUCCESS");
      return sendSuccess(res, settlement, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateSettlement(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const settlement = await AdminService.updateSettlement(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Settlement", id, "SUCCESS");
      return sendSuccess(res, settlement);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteSettlement(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteSettlement(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Settlement", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Transactions CRUD
  public static async createTransaction(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const txn = await AdminService.createTransaction(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Transaction", txn.txn_id, "SUCCESS");
      return sendSuccess(res, txn, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateTransaction(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const txn = await AdminService.updateTransaction(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Transaction", id, "SUCCESS");
      return sendSuccess(res, txn);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteTransaction(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteTransaction(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Transaction", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Banners CRUD
  public static async getBanners(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const banners = await AdminService.getBanners();
      return sendSuccess(res, banners);
    } catch (err) {
      next(err);
    }
  }

  public static async createBanner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const banner = await AdminService.createBanner(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Banner", banner.banner_id, "SUCCESS");
      return sendSuccess(res, banner, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateBanner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const banner = await AdminService.updateBanner(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Banner", id, "SUCCESS");
      return sendSuccess(res, banner);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteBanner(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteBanner(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Banner", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Disputes CRUD extension
  public static async createDispute(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const dispute = await AdminService.createDispute(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Dispute", dispute.dispute_id, "SUCCESS");
      return sendSuccess(res, dispute, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteDispute(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteDispute(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Dispute", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Broadcasts CRUD extension
  public static async deleteBroadcast(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteBroadcast(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Broadcast", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  // Audit Logs CRUD
  public static async getAuditLogs(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const logs = await AdminService.getAuditLogs();
      return sendSuccess(res, logs);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteAuditLogs(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      await AdminService.deleteAuditLogs();
      return sendSuccess(res, { cleared: true });
    } catch (err) {
      next(err);
    }
  }

  // Settings CRUD
  public static async getSettings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const settings = await AdminService.getSettings();
      return sendSuccess(res, settings);
    } catch (err) {
      next(err);
    }
  }

  public static async saveSettings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const settings = await AdminService.saveSettings(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update System Settings", "system", "SUCCESS");
      return sendSuccess(res, settings);
    } catch (err) {
      next(err);
    }
  }

  // Roles CRUD
  public static async getRoles(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const roles = await AdminService.getRoles();
      return sendSuccess(res, roles);
    } catch (err) {
      next(err);
    }
  }

  public static async createRole(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const role = await AdminService.createRole(req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Create Role Profile", role.id, "SUCCESS");
      return sendSuccess(res, role, 201);
    } catch (err) {
      next(err);
    }
  }

  public static async updateRole(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const role = await AdminService.updateRole(id, req.body);
      await AdminService.addAuditLog(req.user?.id || "admin", "Update Role Profile", id, "SUCCESS");
      return sendSuccess(res, role);
    } catch (err) {
      next(err);
    }
  }

  public static async deleteRole(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      await AdminService.deleteRole(id);
      await AdminService.addAuditLog(req.user?.id || "admin", "Delete Role Profile", id, "SUCCESS");
      return sendSuccess(res, { deleted: true });
    } catch (err) {
      next(err);
    }
  }

  public static async getAllChatMessages(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const messages = await AdminService.getAllChatMessages();
      return sendSuccess(res, messages);
    } catch (err) {
      next(err);
    }
  }
}
export default AdminController;

