import { Router } from 'express';
import { ClientController } from './client.controller.js';
import { authenticate } from '../../middleware/authenticate.js';
import { authorize } from '../../middleware/authorize.js';
import { googleLoginLimiter, otpRequestLimiter, otpVerifyLimiter, paymentVerifyLimiter } from '../../middleware/rateLimit.js';
import { upload, uploadPrivate } from '../../middleware/upload.js';

export const clientRoutes = Router();

// Public Authentication (rate-limited brute-force protection)
clientRoutes.post('/auth/request-otp', otpRequestLimiter, ClientController.requestOtp);
clientRoutes.post('/auth/verify-otp', otpVerifyLimiter, ClientController.verifyOtp);
clientRoutes.post('/auth/google', googleLoginLimiter, ClientController.googleLogin);

// Razorpay webhook: public, verified by HMAC over the raw body (raw parser
// is mounted for this exact path in app.ts before express.json).
clientRoutes.post('/payments/webhook', ClientController.razorpayWebhook);

// Public Venues & Banners Discovery
clientRoutes.get('/venues', ClientController.getVenues);
clientRoutes.get('/venues/:id', ClientController.getVenueDetails);
clientRoutes.get('/venues/:venueId/slots', ClientController.getVenueSlots);
clientRoutes.get('/content/banners', ClientController.getBanners);
clientRoutes.get('/content/settings', ClientController.getSystemSettings);

// Guarded Routes (Users & Partners)
clientRoutes.use(authenticate);

// File Upload Routes
// Public: venue images, avatars, banners (served statically).
clientRoutes.post('/upload', upload.single('file'), ClientController.uploadFile);
// Private: KYC / identity / bank documents (never served statically).
clientRoutes.post('/partner/kyc/upload', authorize('partner'), uploadPrivate.single('file'), ClientController.uploadKycFile);
clientRoutes.get('/partner/kyc/:docId/file', authorize('partner'), ClientController.downloadKycFile);

// Profile
clientRoutes.get('/users/me', ClientController.getProfile);
clientRoutes.patch('/users/me', ClientController.updateProfile);
clientRoutes.delete('/users/me', ClientController.deleteProfile);

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
clientRoutes.post('/payments/verify', paymentVerifyLimiter, ClientController.verifyPayment);
clientRoutes.post('/payments/wallet/initiate', ClientController.initiateWalletPayment);
clientRoutes.post('/payments/wallet/verify', paymentVerifyLimiter, ClientController.verifyWalletPayment);

// Coupons & Tournaments
clientRoutes.get('/coupons', ClientController.getCoupons);
clientRoutes.get('/tournaments', ClientController.getTournaments);
clientRoutes.post('/tournaments/:tournamentId/register', ClientController.registerTournament);

// Notifications & Chat
clientRoutes.get('/notifications', ClientController.getNotifications);
clientRoutes.patch('/notifications/:id/read', ClientController.readNotification);
clientRoutes.get('/chat/history', ClientController.getChatHistory);
clientRoutes.post('/chat/send', ClientController.sendChatMessage);
clientRoutes.post('/reports', ClientController.reportProblem);


// Partner Operations (partner role enforced at route + service level)
clientRoutes.get('/partner/venues', authorize('partner'), ClientController.getPartnerVenues);
clientRoutes.post('/partner/venues', authorize('partner'), ClientController.createPartnerVenue);
clientRoutes.patch('/partner/venues/:id', authorize('partner'), ClientController.updatePartnerVenue);
clientRoutes.get('/partner/venues/:venueId/slots', authorize('partner'), ClientController.getPartnerVenueSlots);
clientRoutes.post('/partner/venues/:venueId/slots/bulk', authorize('partner'), ClientController.bulkGenerateSlots);
clientRoutes.delete('/partner/venues/:venueId/slots/bulk', authorize('partner'), ClientController.bulkDeleteSlots);
clientRoutes.patch('/partner/slots/:id/block', authorize('partner'), ClientController.toggleSlotBlock);
clientRoutes.get('/partner/bookings', authorize('partner'), ClientController.getPartnerBookings);
clientRoutes.patch('/partner/bookings/:id/checkin', authorize('partner'), ClientController.checkinBooking);
clientRoutes.get('/partner/disputes', authorize('partner'), ClientController.getPartnerDisputes);
clientRoutes.post('/partner/disputes', authorize('partner'), ClientController.createPartnerDispute);
clientRoutes.get('/partner/settlements', authorize('partner'), ClientController.getPartnerSettlements);
clientRoutes.get('/partner/reviews', authorize('partner'), ClientController.getPartnerReviews);
clientRoutes.post('/partner/reviews/:id/reply', authorize('partner'), ClientController.replyToReview);
clientRoutes.post('/partner/kyc', authorize('partner'), ClientController.submitPartnerKyc);

export default clientRoutes;
