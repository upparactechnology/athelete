import { Response, NextFunction } from 'express';
import { ClientService } from './client.service.js';
import { AuthRequest } from '../../shared/types/index.js';
import { prisma } from '../../config/prisma.js';
import { AdminService } from '../admin/admin.service.js';

export class ClientController {
  // 1. Auth Handlers
  public static async requestOtp(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { phoneNumber } = req.body;
      const data = await ClientService.requestOtp(phoneNumber);
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
      const data = await ClientService.cancelBooking(id, userId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  // 6. Payments Handlers
  public static async initiatePayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { bookingId } = req.body;
      const data = await ClientService.initiatePayment(bookingId);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async verifyPayment(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { bookingId, razorpayOrderId, razorpayPaymentId } = req.body;
      const data = await ClientService.verifyPayment(bookingId, razorpayOrderId, razorpayPaymentId);
      res.status(200).json({ success: true, data });
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
      const data = await ClientService.readNotification(id);
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
      const partnerId = req.user?.id;
      const data = await ClientService.getPartnerVenues(partnerId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createPartnerVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const data = await ClientService.createPartnerVenue(partnerId!, req.body);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async updatePartnerVenue(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const { id } = req.params;
      const data = await ClientService.updatePartnerVenue(partnerId!, id, req.body);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerVenueSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { venueId } = req.params;
      const { date } = req.query;
      const data = await ClientService.getPartnerVenueSlots(venueId, date as string);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async bulkGenerateSlots(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { venueId } = req.params;
      const { date, startTime, endTime, price, durationMinutes } = req.body;
      const data = await ClientService.bulkGenerateSlots(venueId, date, startTime, endTime, Number(price), Number(durationMinutes));
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async toggleSlotBlock(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const data = await ClientService.toggleSlotBlock(id);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerBookings(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const data = await ClientService.getPartnerBookings(partnerId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async checkinBooking(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const data = await ClientService.checkinBooking(id);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerDisputes(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const data = await ClientService.getPartnerDisputes(partnerId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createPartnerDispute(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { bookingId, details } = req.body;
      const data = await ClientService.createPartnerDispute(bookingId, details);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerSettlements(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const data = await ClientService.getPartnerSettlements(partnerId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async getPartnerReviews(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const data = await ClientService.getPartnerReviews(partnerId!);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async replyToReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { reply } = req.body;
      const data = await ClientService.replyToReview(id, reply);
      res.status(200).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async submitPartnerKyc(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const partnerId = req.user?.id;
      const { documentType, fileUrl } = req.body;
      const data = await ClientService.submitPartnerKyc(partnerId!, documentType, fileUrl);
      res.status(201).json({ success: true, data });
    } catch (err) {
      next(err);
    }
  }

  public static async createVenueReview(req: AuthRequest, res: Response, next: NextFunction) {
    try {
      const userId = req.user?.id;
      const { venueId } = req.params;
      const { rating, comment, bookingId } = req.body;
      
      let finalBookingId = bookingId;
      if (!finalBookingId) {
        const booking = await prisma.booking.findFirst({
          where: {
            user_id: userId,
            venue_id: venueId,
          },
          orderBy: { created_at: 'desc' }
        });
        if (booking) {
          finalBookingId = booking.booking_id;
        }
      }

      if (!finalBookingId) {
        const dummySlot = await prisma.slot.findFirst({ where: { venue_id: venueId } });
        if (dummySlot) {
          const newBooking = await prisma.booking.create({
            data: {
              user_id: userId!,
              venue_id: venueId,
              slot_id: dummySlot.slot_id,
              status: 'CONFIRMED',
              payment_mode: 'free',
              eticket_code: `APV-${Date.now()}-${Math.floor(Math.random()*1000)}`,
              convenience_fee: 0,
              commission_amount: 0,
              gst_amount: 0,
              partner_amount: 0,
              online_amount: 0,
              venue_amount: 0,
            }
          });
          finalBookingId = newBooking.booking_id;
        } else {
          throw new Error("Cannot review this venue: no slots available");
        }
      }

      const review = await prisma.venueReview.create({
        data: {
          venue_id: venueId,
          user_id: userId!,
          booking_id: finalBookingId,
          rating: parseInt(rating.toString()),
          comment
        },
        include: {
          user: true
        }
      });

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
      const { recipientId, text } = req.body;
      const data = await ClientService.sendChatMessage(userId, recipientId, text);
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
          supportEmail: settings.supportEmail
        }
      });
    } catch (err) {
      next(err);
    }
  }
}
