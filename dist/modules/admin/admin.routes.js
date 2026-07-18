import { Router } from 'express';
import { AdminController } from './admin.controller.js';
import { authenticate } from '../../middleware/authenticate.js';
import { authorize } from '../../middleware/authorize.js';
export const adminRoutes = Router();
// Public login endpoint
adminRoutes.post('/login', AdminController.login);
// Guarded administrative endpoints (requires authenticated Admin with double-header checks)
adminRoutes.use(authenticate, authorize('admin'));
adminRoutes.get('/stats', AdminController.getDashboardStats);
// Users CRUD
adminRoutes.get('/users', AdminController.getUsers);
adminRoutes.post('/users', AdminController.createUser);
adminRoutes.patch('/users/:id/status', AdminController.updateUserStatus);
adminRoutes.patch('/users/:id', AdminController.updateUser);
adminRoutes.delete('/users/:id', AdminController.deleteUser);
// Partners CRUD
adminRoutes.get('/partners', AdminController.getPartners);
adminRoutes.post('/partners', AdminController.createPartner);
adminRoutes.patch('/partners/:id', AdminController.updatePartner);
adminRoutes.delete('/partners/:id', AdminController.deletePartner);
adminRoutes.patch('/partners/:id/bank-approve', AdminController.approveBankDetails);
adminRoutes.patch('/partners/:id/bank-reject', AdminController.rejectBankDetails);
adminRoutes.get('/kyc/pending', AdminController.getPendingKycDocuments);
adminRoutes.patch('/kyc/document/:id', AdminController.updateKycDocumentStatus);
// Venues CRUD
adminRoutes.get('/venues', AdminController.getAllVenues);
adminRoutes.post('/venues', AdminController.createVenue);
adminRoutes.patch('/venues/:id/status', AdminController.updateVenueStatus);
adminRoutes.patch('/venues/:id/feature', AdminController.toggleVenueFeatured);
adminRoutes.patch('/venues/:id', AdminController.updateVenue);
adminRoutes.delete('/venues/:id', AdminController.deleteVenue);
// Bookings CRUD
adminRoutes.get('/bookings', AdminController.getAllBookings);
adminRoutes.post('/bookings', AdminController.createBooking);
adminRoutes.patch('/bookings/:id/cancel', AdminController.cancelBooking);
adminRoutes.patch('/bookings/:id/reassign', AdminController.reassignBookingSlot);
adminRoutes.patch('/bookings/:id', AdminController.updateBooking);
adminRoutes.delete('/bookings/:id', AdminController.deleteBooking);
// Transactions CRUD
adminRoutes.get('/transactions', AdminController.getTransactions);
adminRoutes.post('/transactions', AdminController.createTransaction);
adminRoutes.patch('/transactions/:id', AdminController.updateTransaction);
adminRoutes.delete('/transactions/:id', AdminController.deleteTransaction);
// Coupons CRUD
adminRoutes.get('/coupons', AdminController.getCoupons);
adminRoutes.post('/coupons', AdminController.createCoupon);
adminRoutes.patch('/coupons/:id', AdminController.updateCoupon);
adminRoutes.delete('/coupons/:id', AdminController.deleteCoupon);
// Disputes CRUD
adminRoutes.get('/disputes', AdminController.getDisputes);
adminRoutes.post('/disputes', AdminController.createDispute);
adminRoutes.patch('/disputes/:id/resolve', AdminController.resolveDispute);
adminRoutes.delete('/disputes/:id', AdminController.deleteDispute);
// Broadcasts CRUD
adminRoutes.post('/broadcast', AdminController.broadcastNotification);
adminRoutes.get('/broadcasts', AdminController.getBroadcasts);
adminRoutes.delete('/broadcasts/:id', AdminController.deleteBroadcast);
adminRoutes.get('/venues/:venueId/slots', AdminController.getVenueSlots);
adminRoutes.post('/slots/demand-tag', AdminController.applyDemandTag);
adminRoutes.delete('/slots/demand-tag', AdminController.removeDemandTag);
// Tournaments CRUD
adminRoutes.get('/tournaments', AdminController.getTournaments);
adminRoutes.post('/tournaments', AdminController.createTournament);
adminRoutes.patch('/tournaments/:id', AdminController.updateTournament);
adminRoutes.delete('/tournaments/:id', AdminController.deleteTournament);
// Reviews CRUD
adminRoutes.get('/reviews', AdminController.getReviews);
adminRoutes.post('/reviews', AdminController.createReview);
adminRoutes.patch('/reviews/:id', AdminController.updateReview);
adminRoutes.delete('/reviews/:id', AdminController.deleteReview);
// Settlements CRUD
adminRoutes.get('/settlements', AdminController.getSettlements);
adminRoutes.post('/settlements', AdminController.createSettlement);
adminRoutes.patch('/settlements/:id', AdminController.updateSettlement);
adminRoutes.delete('/settlements/:id', AdminController.deleteSettlement);
// Banners CRUD
adminRoutes.get('/banners', AdminController.getBanners);
adminRoutes.post('/banners', AdminController.createBanner);
adminRoutes.patch('/banners/:id', AdminController.updateBanner);
adminRoutes.delete('/banners/:id', AdminController.deleteBanner);
// Audit Logs CRUD
adminRoutes.get('/audit-logs', AdminController.getAuditLogs);
adminRoutes.delete('/audit-logs', AdminController.deleteAuditLogs);
// Settings CRUD
adminRoutes.get('/settings', AdminController.getSettings);
adminRoutes.post('/settings', AdminController.saveSettings);
// Roles CRUD
adminRoutes.get('/roles', AdminController.getRoles);
adminRoutes.post('/roles', AdminController.createRole);
adminRoutes.patch('/roles/:id', AdminController.updateRole);
adminRoutes.delete('/roles/:id', AdminController.deleteRole);
// Support Chat History & Reply
adminRoutes.get('/chat/messages', AdminController.getAllChatMessages);
export default adminRoutes;
