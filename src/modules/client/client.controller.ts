import { Response, NextFunction } from 'express';
import { ClientService } from './client.service.js';
import { AuthRequest } from '../../shared/types/index.js';

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
      const { city, sport } = req.query;
      const data = await ClientService.getVenues(city as string, sport as string);
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
}
