import { Response, NextFunction } from 'express';
import { ClientService } from './client.service.js';
import { AuthRequest } from '../../shared/types/index.js';
import { prisma } from '../../config/prisma.js';
import { AdminService } from '../admin/admin.service.js';
import { ConflictError, ForbiddenError, ValidationError } from '../../shared/utils/errors.js';
import { resolvePrivateFile, validateUploadedFileContent } from '../../middleware/upload.js';
import { SAFE_USER_PUBLIC_SELECT } from '../../shared/utils/bookingPrivacy.js';
import { ensureReviewEligible } from '../../shared/utils/bookingLifecycle.js';

function requirePartner(req: AuthRequest): string {
  if (!req.user || req.user.role !== 'partner') {
    throw new ForbiddenError("Partner access required");
  }
  return req.user.id;
}

export class ClientController {
  // 1. Auth Handlers
  public static async requestOtp(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { phoneNumber, password, isSignUp, role } = req.body;
      const data = await ClientService.requestOtp(phoneNumber, password, isSignUp, role || 'partner');
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async verifyOtp(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { phoneNumber, otp, role } = req.body;
      const data = await ClientService.verifyOtp(phoneNumber, otp, role || 'user');
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async login(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      // Direct email/phone + password login (no OTP). The identifier may be
      // an email address or phone number; the role selects the account table.
      const { phoneNumber, password, role } = req.body;
      const data = await ClientService.login(phoneNumber, password, role || 'partner');
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async googleLogin(req: any, res: Response, next: NextFunction) {
    try {
      // The app must send the Google ID token. Email/name from the client
      // are NEVER accepted as proof of identity (P0).
      const { idToken, role } = req.body;
      const data = await ClientService.googleLogin(idToken, role);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 2. Profile Handlers
  public static async getProfile(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const id = req.user?.id;
      const role = req.user?.role;
      const data = await ClientService.getProfile(id!, role!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async updateProfile(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const id = req.user?.id;
      const role = req.user?.role;
      const data = await ClientService.updateProfile(id!, req.body, role!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async deleteProfile(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const id = req.user?.id;
      const role = req.user?.role;
      const data = await ClientService.deleteProfile(id!, role!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 3. Wishlist Handlers
  public static async getWishlist(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const data = await ClientService.getWishlist(userId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async toggleWishlist(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { venueId } = req.params;
      const data = await ClientService.toggleWishlist(userId!, venueId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 4. Venues & Slots Catalog Handlers
  public static async getVenues(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { city, sport, lat, lng } = req.query;
      const data = await ClientService.getVenues(city as string, sport as string, lat as string, lng as string);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getVenueDetails(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const data = await ClientService.getVenueDetails(id);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getVenueSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { venueId } = req.params;
      const { date } = req.query;
      const data = await ClientService.getVenueSlots(venueId, date as string);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 5. Bookings Handlers
  public static async getBookings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const data = await ClientService.getBookings(userId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { venueId, slotId, paymentMode, couponCode } = req.body;
      const data = await ClientService.createBooking(userId!, venueId, slotId, paymentMode, couponCode);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async cancelBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { id } = req.params;
      // `pendingOnly` is the payment-failure auto-release path: the server
      // cancels ONLY a still-PENDING booking and answers 409 NOT_PENDING
      // (with details.status) otherwise, so a client can never cancel a
      // booking that a webhook/verification has just confirmed.
      const pendingOnly = req.body?.pendingOnly === true;
      const data = await ClientService.cancelBooking(id, userId!, { pendingOnly });
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 6. Payments Handlers
  public static async initiatePayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { bookingId } = req.body;
      const data = await ClientService.initiatePayment(bookingId, userId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async verifyPayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { bookingId, razorpayOrderId, razorpayPaymentId, razorpaySignature } = req.body;
      const data = await ClientService.verifyPayment(bookingId, userId!, razorpayOrderId, razorpayPaymentId, razorpaySignature);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  /**
   * Razorpay webhook. The raw body parser in app.ts preserves the Buffer;
   * signature is verified over raw bytes inside the service (P0).
   */
  public static async razorpayWebhook(req: any, res: Response, next: NextFunction) {
    try {
      const rawBody: Buffer = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body ? JSON.stringify(req.body) : '');
      const signature = req.headers['x-razorpay-signature'] as string | undefined;
      const data = await ClientService.handleRazorpayWebhook(rawBody, signature);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async initiateWalletPayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { amount } = req.body;
      const data = await ClientService.initiateWalletPayment(amount);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async verifyWalletPayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { razorpayOrderId, razorpayPaymentId, amount, razorpaySignature } = req.body;
      const data = await ClientService.verifyWalletPayment(userId!, razorpayOrderId, razorpayPaymentId, amount, razorpaySignature);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // P2-7: session rotation (public; rate-limited at the route).
  public static async refreshAccessToken(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { refreshToken } = req.body;
      const data = await ClientService.refreshAccessToken(refreshToken);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // P2-7: logout (revokes the presented refresh session; idempotent).
  public static async logout(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { refreshToken } = req.body;
      const data = await ClientService.logout(refreshToken);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // P2-3: user-initiated refund for own booking (server-computed amount).
  public static async requestRefund(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { bookingId } = req.body;
      const data = await ClientService.requestRefund(userId!, bookingId);
      res.status(200).json({ success: true, data: { ...data, refundTxn: undefined, refundId: (data.refundTxn as any)?.txn_id } });
    } catch (err) {
      next(err);
    }
  }

  // 7. Coupons Handlers
  public static async getCoupons(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const data = await ClientService.getCoupons();
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 8. Tournaments Handlers
  public static async getTournaments(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const data = await ClientService.getTournaments();
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async registerTournament(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { tournamentId } = req.params;
      const { teamName } = req.body;
      const data = await ClientService.registerTournament(userId!, tournamentId, teamName);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // P2-5: cancel own tournament registration (frees capacity exactly once).
  public static async cancelTournamentRegistration(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { tournamentId } = req.params;
      const data = await ClientService.cancelTournamentRegistration(userId!, tournamentId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 9. Notifications Handlers
  public static async getNotifications(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const id = req.user?.id;
      const role = req.user?.role;
      const data = await ClientService.getNotifications(id!, role!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async readNotification(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const data = await ClientService.readNotification(id, req.user?.id);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getChatHistory(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const data = await ClientService.getChatHistory(userId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }


  // 10. Banners Handlers
  public static async getBanners(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const target = req.query.target as string || 'user';
      const data = await ClientService.getBanners(target);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // Partner Handlers
  public static async getPartnerVenues(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.getPartnerVenues(partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createPartnerVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.createPartnerVenue(partnerId, req.body);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async updatePartnerVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { id } = req.params;
      const data = await ClientService.updatePartnerVenue(partnerId, id, req.body);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerVenueSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { venueId } = req.params;
      const { date } = req.query;
      const data = await ClientService.getPartnerVenueSlots(venueId, date as string, partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async bulkGenerateSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { venueId } = req.params;
      const { date, dates, startTime, endTime, price, durationMinutes } = req.body;
      const targetDates = Array.isArray(dates) ? dates : (date ? [date] : []);
      const data = await ClientService.bulkGenerateSlots(venueId, targetDates, startTime, endTime, Number(price), Number(durationMinutes), partnerId);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async bulkDeleteSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { venueId } = req.params;
      const { slotIds } = req.body;
      const data = await ClientService.bulkDeleteSlots(venueId, slotIds || [], partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async toggleSlotBlock(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { id } = req.params;
      const data = await ClientService.toggleSlotBlock(id, partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerBookings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.getPartnerBookings(partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async checkinBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { id } = req.params;
      const data = await ClientService.checkinBooking(id, partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async collectVenueCash(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { id } = req.params;
      const data = await ClientService.collectVenueCash(id, partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerDisputes(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.getPartnerDisputes(partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createPartnerDispute(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { bookingId, details } = req.body;
      const data = await ClientService.createPartnerDispute(bookingId, details, partnerId);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerSettlements(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.getPartnerSettlements(partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerReviews(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const data = await ClientService.getPartnerReviews(partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async replyToReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { id } = req.params;
      const { reply } = req.body;
      const data = await ClientService.replyToReview(id, reply, partnerId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async submitPartnerKyc(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { documentType, fileUrl, gstNumber, panNumber, aadhaarNumber } = req.body;
      const data = await ClientService.submitPartnerKyc(partnerId, documentType, fileUrl, gstNumber, panNumber, aadhaarNumber);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createVenueReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const role = req.user?.role || 'user';
      const { venueId } = req.params;
      const { rating, comment, bookingId } = req.body;

      // P2-6: only players may review, only from their own CONFIRMED/COMPLETED
      // booking for this venue, one review per booking. No fabricated bookings.
      if (role !== 'user') {
        throw new ForbiddenError("Only players may submit venue reviews");
      }
      const ratingNum = parseInt(String(rating), 10);
      if (!Number.isFinite(ratingNum) || ratingNum < 1 || ratingNum > 5) {
        throw new ValidationError("Rating must be between 1 and 5");
      }
      if (!comment || !String(comment).trim()) {
        throw new ValidationError("Review comment is required");
      }

      let booking: any = null;
      if (bookingId) {
        booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
        ensureReviewEligible(booking, userId!, venueId, role);
      } else {
        booking = await prisma.booking.findFirst({
          where: {
            user_id: userId,
            venue_id: venueId,
            status: { in: ['CONFIRMED', 'COMPLETED'] },
          },
          orderBy: { created_at: 'desc' }
        });
        ensureReviewEligible(booking, userId!, venueId, role);
      }

      let review;
      try {
        review = await prisma.venueReview.create({
          data: {
            venue_id: venueId,
            user_id: userId!,
            booking_id: booking.booking_id,
            rating: ratingNum,
            comment: String(comment).trim()
          },
          include: {
            user: { select: SAFE_USER_PUBLIC_SELECT }
          }
        });
      } catch (err: any) {
        if (err?.code === 'P2002') {
          throw new ConflictError("You have already reviewed this booking", "DUPLICATE_REVIEW");
        }
        throw err;
      }

      const allReviews = await prisma.venueReview.findMany({
        where: { venue_id: venueId }
      });
      const avg = allReviews.reduce((sum, r) => sum + r.rating, 0) / allReviews.length;
      await prisma.venue.update({
        where: { venue_id: venueId },
        data: { avg_rating: avg }
      });

      res.status(201).json({ success: true, data: review });
    } catch (err) {
      next(err);
    }
  }

  public static async sendChatMessage(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      if (!userId) throw new Error("Unauthorized");
      const role = req.user?.role === 'partner' ? 'partner' : req.user?.role === 'admin' ? 'admin' : 'user';
      const { recipientId, text } = req.body;
      const data = await ClientService.sendChatMessage(userId, recipientId, text, role);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getSystemSettings(req: any, res: Response, next: NextFunction) {
    try {
      const settings = await AdminService.getSettings();
      res.status(200).json({
        success: true,
        data: {
          supportPhone: settings.supportPhone || "9427961426",
          supportWhatsapp: settings.supportWhatsapp || "9427961426",
          supportEmail: settings.supportEmail || "support@athletepov.com",
          partnerAppVersion: settings.partnerAppVersion || "1.0.24",
          playerAppVersion: settings.playerAppVersion || "1.0.12",
          privacyPolicyUrl: settings.privacyPolicyUrl || "https://athletepov.com/privacy-policy",
          termsOfServiceUrl: settings.termsOfServiceUrl || "https://athletepov.com/terms-of-service",
          playStoreUrl: settings.playStoreUrl || "https://play.google.com/store/apps/details?id=com.athletepov.partner",
          appStoreUrl: settings.appStoreUrl || "https://apps.apple.com/app/athletepov-partner/id123456789"
        }
      });
    } catch (err) {
      next(err);
    }
  }

  public static async reportProblem(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { title, description } = req.body;
      const data = await ClientService.reportProblem(userId!, title, description);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async uploadFile(req: any, res: Response, next: NextFunction) {
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, error: { message: "No file uploaded" } });
      }
      // Verify actual content matches the declared type; deletes on mismatch.
      try {
        validateUploadedFileContent(req.file.path, req.file.mimetype);
      } catch (e: any) {
        return res.status(400).json({ success: false, error: { code: 'INVALID_FILE', message: e.message || 'Invalid file content' } });
      }

      const category = req.body?.category === 'kyc' || req.query?.category === 'kyc' ? 'kyc' : 'public';
      if (category === 'kyc') {
        // Private document: stored outside the static dir. The returned ref
        // (NOT a URL) is submitted with the KYC request; download requires
        // ownership via GET /partner/kyc/:docId/file.
        return res.status(200).json({
          success: true,
          data: {
            ref: `private:${req.file.filename}`,
            filename: req.file.filename,
            category: 'private'
          }
        });
      }

      const settings = await AdminService.getSettings();
      const provider = settings.storageProvider || 'local';
      const fileUrl = `${req.protocol}://${req.get('host')}/uploads/${req.file.filename}`;

      res.status(200).json({
        success: true,
        data: {
          url: fileUrl,
          filename: req.file.filename,
          provider,
          category: 'public'
        }
      });
    } catch (err) {
      next(err);
    }
  }

  /**
   * Private KYC document upload (P0). Uses the private multer instance;
   * returns an opaque ref for submitPartnerKyc, never a public URL.
   */
  public static async uploadKycFile(req: any, res: Response, next: NextFunction) {
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, error: { message: "No file uploaded" } });
      }
      try {
        validateUploadedFileContent(req.file.path, req.file.mimetype);
      } catch (e: any) {
        return res.status(400).json({ success: false, error: { code: 'INVALID_FILE', message: e.message || 'Invalid file content' } });
      }
      return res.status(200).json({
        success: true,
        data: {
          ref: `private:${req.file.filename}`,
          filename: req.file.filename,
          category: 'private'
        }
      });
    } catch (err) {
      next(err);
    }
  }
  public static async downloadKycFile(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = requirePartner(req);
      const { docId } = req.params;
      const doc = await prisma.partnerDocument.findFirst({
        where: { doc_id: docId, partner_id: partnerId }
      });
      if (!doc) {
        return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Document not found' } });
      }
      const ref = doc.file_url || '';
      const filename = ref.startsWith('private:') ? ref.slice('private:'.length) : null;
      if (!filename) {
        return res.status(410).json({ success: false, error: { code: 'GONE', message: 'Document file is no longer available' } });
      }
      const abs = resolvePrivateFile(filename);
      return res.sendFile(abs);
    } catch (err) {
      next(err);
    }
  }
}
