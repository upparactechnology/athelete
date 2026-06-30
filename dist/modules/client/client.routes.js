import { Router } from 'express';
import { ClientController } from './client.controller.js';
import { authenticate } from '../../middleware/authenticate.js';
export const clientRoutes = Router();
// Public Authentication
clientRoutes.post('/auth/request-otp', ClientController.requestOtp);
clientRoutes.post('/auth/verify-otp', ClientController.verifyOtp);
// Public Venues & Banners Discovery
clientRoutes.get('/venues', ClientController.getVenues);
clientRoutes.get('/venues/:id', ClientController.getVenueDetails);
clientRoutes.get('/venues/:venueId/slots', ClientController.getVenueSlots);
clientRoutes.get('/content/banners', ClientController.getBanners);
// Guarded Routes (Users & Partners)
clientRoutes.use(authenticate);
// Profile
clientRoutes.get('/users/me', ClientController.getProfile);
clientRoutes.patch('/users/me', ClientController.updateProfile);
// Wishlist
clientRoutes.get('/users/me/wishlist', ClientController.getWishlist);
clientRoutes.post('/users/me/wishlist/:venueId', ClientController.toggleWishlist);
clientRoutes.post('/venues/:venueId/reviews', ClientController.createVenueReview);
// Bookings
clientRoutes.get('/bookings', ClientController.getBookings);
clientRoutes.post('/bookings', ClientController.createBooking);
clientRoutes.patch('/bookings/:id/cancel', ClientController.cancelBooking);
// Payments
clientRoutes.post('/payments/initiate', ClientController.initiatePayment);
clientRoutes.post('/payments/verify', ClientController.verifyPayment);
// Coupons & Tournaments
clientRoutes.get('/coupons', ClientController.getCoupons);
clientRoutes.get('/tournaments', ClientController.getTournaments);
clientRoutes.post('/tournaments/:tournamentId/register', ClientController.registerTournament);
// Notifications & Chat
clientRoutes.get('/notifications', ClientController.getNotifications);
clientRoutes.patch('/notifications/:id/read', ClientController.readNotification);
clientRoutes.get('/chat/history', ClientController.getChatHistory);
// Partner Operations
clientRoutes.get('/partner/venues', ClientController.getPartnerVenues);
clientRoutes.post('/partner/venues', ClientController.createPartnerVenue);
clientRoutes.patch('/partner/venues/:id', ClientController.updatePartnerVenue);
clientRoutes.get('/partner/venues/:venueId/slots', ClientController.getPartnerVenueSlots);
clientRoutes.post('/partner/venues/:venueId/slots/bulk', ClientController.bulkGenerateSlots);
clientRoutes.patch('/partner/slots/:id/block', ClientController.toggleSlotBlock);
clientRoutes.get('/partner/bookings', ClientController.getPartnerBookings);
clientRoutes.patch('/partner/bookings/:id/checkin', ClientController.checkinBooking);
clientRoutes.get('/partner/disputes', ClientController.getPartnerDisputes);
clientRoutes.post('/partner/disputes', ClientController.createPartnerDispute);
clientRoutes.get('/partner/settlements', ClientController.getPartnerSettlements);
clientRoutes.get('/partner/reviews', ClientController.getPartnerReviews);
clientRoutes.post('/partner/reviews/:id/reply', ClientController.replyToReview);
clientRoutes.post('/partner/kyc', ClientController.submitPartnerKyc);
export default clientRoutes;
