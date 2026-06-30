import { ClientService } from './client.service.js';
import { prisma } from '../../config/prisma.js';
import { AdminService } from '../admin/admin.service.js';
export class ClientController {
    // 1. Auth Handlers
    static async requestOtp(req, res, next) {
        try {
            const { phoneNumber } = req.body;
            const data = await ClientService.requestOtp(phoneNumber);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async verifyOtp(req, res, next) {
        try {
            const { phoneNumber, otp, role } = req.body;
            const data = await ClientService.verifyOtp(phoneNumber, otp, role || 'user');
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 2. Profile Handlers
    static async getProfile(req, res, next) {
        try {
            const id = req.user?.id;
            const role = req.user?.role;
            const data = await ClientService.getProfile(id, role);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async updateProfile(req, res, next) {
        try {
            const id = req.user?.id;
            const role = req.user?.role;
            const data = await ClientService.updateProfile(id, req.body, role);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 3. Wishlist Handlers
    static async getWishlist(req, res, next) {
        try {
            const userId = req.user?.id;
            const data = await ClientService.getWishlist(userId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async toggleWishlist(req, res, next) {
        try {
            const userId = req.user?.id;
            const { venueId } = req.params;
            const data = await ClientService.toggleWishlist(userId, venueId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 4. Venues & Slots Catalog Handlers
    static async getVenues(req, res, next) {
        try {
            const { city, sport, lat, lng } = req.query;
            const data = await ClientService.getVenues(city, sport, lat, lng);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getVenueDetails(req, res, next) {
        try {
            const { id } = req.params;
            const data = await ClientService.getVenueDetails(id);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getVenueSlots(req, res, next) {
        try {
            const { venueId } = req.params;
            const { date } = req.query;
            const data = await ClientService.getVenueSlots(venueId, date);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 5. Bookings Handlers
    static async getBookings(req, res, next) {
        try {
            const userId = req.user?.id;
            const data = await ClientService.getBookings(userId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async createBooking(req, res, next) {
        try {
            const userId = req.user?.id;
            const { venueId, slotId, paymentMode, couponCode } = req.body;
            const data = await ClientService.createBooking(userId, venueId, slotId, paymentMode, couponCode);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async cancelBooking(req, res, next) {
        try {
            const userId = req.user?.id;
            const { id } = req.params;
            const data = await ClientService.cancelBooking(id, userId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 6. Payments Handlers
    static async initiatePayment(req, res, next) {
        try {
            const { bookingId } = req.body;
            const data = await ClientService.initiatePayment(bookingId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async verifyPayment(req, res, next) {
        try {
            const { bookingId, razorpayOrderId, razorpayPaymentId } = req.body;
            const data = await ClientService.verifyPayment(bookingId, razorpayOrderId, razorpayPaymentId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 7. Coupons Handlers
    static async getCoupons(req, res, next) {
        try {
            const data = await ClientService.getCoupons();
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 8. Tournaments Handlers
    static async getTournaments(req, res, next) {
        try {
            const data = await ClientService.getTournaments();
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async registerTournament(req, res, next) {
        try {
            const userId = req.user?.id;
            const { tournamentId } = req.params;
            const { teamName } = req.body;
            const data = await ClientService.registerTournament(userId, tournamentId, teamName);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 9. Notifications Handlers
    static async getNotifications(req, res, next) {
        try {
            const id = req.user?.id;
            const role = req.user?.role;
            const data = await ClientService.getNotifications(id, role);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async readNotification(req, res, next) {
        try {
            const { id } = req.params;
            const data = await ClientService.readNotification(id);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getChatHistory(req, res, next) {
        try {
            const userId = req.user?.id;
            const data = await ClientService.getChatHistory(userId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // 10. Banners Handlers
    static async getBanners(req, res, next) {
        try {
            const target = req.query.target || 'user';
            const data = await ClientService.getBanners(target);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    // Partner Handlers
    static async getPartnerVenues(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.getPartnerVenues(partnerId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async createPartnerVenue(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.createPartnerVenue(partnerId, req.body);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async updatePartnerVenue(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const { id } = req.params;
            const data = await ClientService.updatePartnerVenue(partnerId, id, req.body);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getPartnerVenueSlots(req, res, next) {
        try {
            const { venueId } = req.params;
            const { date } = req.query;
            const data = await ClientService.getPartnerVenueSlots(venueId, date);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async bulkGenerateSlots(req, res, next) {
        try {
            const { venueId } = req.params;
            const { date, startTime, endTime, price, durationMinutes } = req.body;
            const data = await ClientService.bulkGenerateSlots(venueId, date, startTime, endTime, Number(price), Number(durationMinutes));
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async toggleSlotBlock(req, res, next) {
        try {
            const { id } = req.params;
            const data = await ClientService.toggleSlotBlock(id);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getPartnerBookings(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.getPartnerBookings(partnerId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async checkinBooking(req, res, next) {
        try {
            const { id } = req.params;
            const data = await ClientService.checkinBooking(id);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getPartnerDisputes(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.getPartnerDisputes(partnerId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async createPartnerDispute(req, res, next) {
        try {
            const { bookingId, details } = req.body;
            const data = await ClientService.createPartnerDispute(bookingId, details);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getPartnerSettlements(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.getPartnerSettlements(partnerId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getPartnerReviews(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const data = await ClientService.getPartnerReviews(partnerId);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async replyToReview(req, res, next) {
        try {
            const { id } = req.params;
            const { reply } = req.body;
            const data = await ClientService.replyToReview(id, reply);
            res.status(200).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async submitPartnerKyc(req, res, next) {
        try {
            const partnerId = req.user?.id;
            const { documentType, fileUrl } = req.body;
            const data = await ClientService.submitPartnerKyc(partnerId, documentType, fileUrl);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async createVenueReview(req, res, next) {
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
                            user_id: userId,
                            venue_id: venueId,
                            slot_id: dummySlot.slot_id,
                            status: 'CONFIRMED',
                            payment_mode: 'free',
                            eticket_code: `APV-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
                            convenience_fee: 0,
                            commission_amount: 0,
                            gst_amount: 0,
                            partner_amount: 0,
                            online_amount: 0,
                            venue_amount: 0,
                        }
                    });
                    finalBookingId = newBooking.booking_id;
                }
                else {
                    throw new Error("Cannot review this venue: no slots available");
                }
            }
            const review = await prisma.venueReview.create({
                data: {
                    venue_id: venueId,
                    user_id: userId,
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
        }
        catch (err) {
            next(err);
        }
    }
    static async sendChatMessage(req, res, next) {
        try {
            const userId = req.user?.id;
            if (!userId)
                throw new Error("Unauthorized");
            const { recipientId, text } = req.body;
            const data = await ClientService.sendChatMessage(userId, recipientId, text);
            res.status(201).json({ success: true, data });
        }
        catch (err) {
            next(err);
        }
    }
    static async getSystemSettings(req, res, next) {
        try {
            const settings = await AdminService.getSettings();
            res.status(200).json({
                success: true,
                data: {
                    supportPhone: settings.supportPhone || "9427961426",
                    supportEmail: settings.supportEmail
                }
            });
        }
        catch (err) {
            next(err);
        }
    }
}
