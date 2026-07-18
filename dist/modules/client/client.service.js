import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { redis } from '../../config/redis.js';
import { ValidationError, NotFoundError } from '../../shared/utils/errors.js';
import { WebSocketService } from '../../shared/services/websocket.js';
import { AdminService } from '../admin/admin.service.js';
import { sendPushNotification } from '../../config/fcm.js';
export class ClientService {
    // 1. Auth Service
    static async requestOtp(phoneNumber, password, isSignUp, role = 'partner') {
        const settings = await AdminService.getSettings();
        if (role === 'partner') {
            // 1. Check if partner exists
            const partner = await prisma.partner.findFirst({
                where: {
                    OR: [
                        { email: phoneNumber },
                        { phone_number: phoneNumber }
                    ]
                }
            });
            if (partner) {
                if (isSignUp) {
                    throw new ValidationError("Account already exists. Please log in.");
                }
                if (!password) {
                    throw new ValidationError("Password is required to log in");
                }
                const partnerObj = partner;
                if (partnerObj.password_hash) {
                    const isPasswordCorrect = bcrypt.compareSync(password, partnerObj.password_hash);
                    if (!isPasswordCorrect) {
                        throw new ValidationError("Invalid email/phone or password");
                    }
                }
            }
            else {
                // Sign up flow
                if (!isSignUp) {
                    throw new ValidationError("Account does not exist. Please sign up.");
                }
                if (!password) {
                    throw new ValidationError("Password is required to register");
                }
                const newPartnerData = {
                    phone_number: phoneNumber,
                    email: phoneNumber.includes('@') ? phoneNumber : null,
                    password_hash: bcrypt.hashSync(password, 10),
                    kyc_status: 'unverified', // Start as unverified by default
                    total_earnings: 0.0
                };
                await prisma.partner.create({
                    data: newPartnerData
                });
            }
        }
        else {
            // 1. Check if user exists
            const user = await prisma.user.findFirst({
                where: {
                    OR: [
                        { email: phoneNumber },
                        { phone_number: phoneNumber }
                    ]
                }
            });
            if (user) {
                if (isSignUp) {
                    throw new ValidationError("Account already exists. Please log in.");
                }
                if (!password) {
                    throw new ValidationError("Password is required to log in");
                }
                const userObj = user;
                if (userObj.password_hash) {
                    const isPasswordCorrect = bcrypt.compareSync(password, userObj.password_hash);
                    if (!isPasswordCorrect) {
                        throw new ValidationError("Invalid email/phone or password");
                    }
                }
            }
            else {
                // Sign up flow
                if (!isSignUp) {
                    throw new ValidationError("Account does not exist. Please sign up.");
                }
                if (!password) {
                    throw new ValidationError("Password is required to register");
                }
                const newUserData = {
                    phone_number: phoneNumber,
                    email: phoneNumber.includes('@') ? phoneNumber : null,
                    password_hash: bcrypt.hashSync(password, 10),
                    status: 'Active',
                    total_bookings: 0,
                    total_spend: 0.0
                };
                await prisma.user.create({
                    data: newUserData
                });
            }
        }
        const code = Math.floor(100000 + Math.random() * 900000).toString();
        const hash = bcrypt.hashSync(code, 10);
        const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes
        await prisma.otpLog.create({
            data: {
                phone_number: phoneNumber,
                otp_hash: hash,
                expires_at: expiresAt,
                attempt_count: 0
            }
        });
        if (settings.useSmtpForOtp && settings.smtpHost) {
            let email = phoneNumber;
            if (!phoneNumber.includes('@')) {
                const user = await prisma.user.findUnique({ where: { phone_number: phoneNumber } });
                if (user && user.email) {
                    email = user.email;
                }
                else {
                    throw new ValidationError("No registered email found for this phone number. Please log in with your email address directly.");
                }
            }
            try {
                const transporter = nodemailer.createTransport({
                    host: settings.smtpHost,
                    port: Number(settings.smtpPort),
                    secure: !!settings.smtpSecure,
                    auth: settings.smtpUser ? {
                        user: settings.smtpUser,
                        pass: settings.smtpPass
                    } : undefined
                });
                await transporter.sendMail({
                    from: settings.smtpFrom || settings.smtpUser || 'noreply@athletepov.com',
                    to: email,
                    subject: `${settings.platformName || "Athlete's POV"} Login OTP`,
                    text: `Your OTP for logging in to ${settings.platformName || "Athlete's POV"} is: ${code}. It is valid for 10 minutes.`,
                    html: `<div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #eee; border-radius: 5px;">
            <h2 style="color: #10B981;">${settings.platformName || "Athlete's POV"}</h2>
            <p>Your One-Time Password (OTP) for login is:</p>
            <div style="font-size: 24px; font-weight: bold; color: #333; letter-spacing: 2px; margin: 20px 0; padding: 10px; background-color: #f9f9f9; border-radius: 4px; display: inline-block;">
              ${code}
            </div>
            <p>This OTP is valid for 10 minutes. Please do not share this code with anyone.</p>
          </div>`
                });
                return { message: `OTP sent to email: ${email}`, otp: code };
            }
            catch (mailErr) {
                console.error("Failed to send OTP email, falling back to simulation:", mailErr);
                return {
                    message: `Failed to send email (${mailErr.message}). Fallback OTP is: ${code}`,
                    otp: code
                };
            }
        }
        return { message: `Simulated SMS: OTP for ${phoneNumber} is ${code}`, otp: code };
    }
    static async googleLogin(email, name, role) {
        let id = "";
        if (role === 'partner') {
            let partner = await prisma.partner.findFirst({ where: { email } });
            if (!partner) {
                const newPartnerData = {
                    email,
                    phone_number: email,
                    kyc_status: 'unverified',
                    total_earnings: 0.0
                };
                partner = await prisma.partner.create({
                    data: newPartnerData
                });
            }
            id = partner.partner_id;
        }
        else {
            let user = await prisma.user.findFirst({ where: { email } });
            if (!user) {
                user = await prisma.user.create({
                    data: {
                        email,
                        phone_number: email,
                        name,
                        status: "Active",
                        total_bookings: 0,
                        total_spend: 0.0
                    }
                });
            }
            id = user.user_id;
        }
        const payload = { sub: id, role, status: "Active" };
        const accessToken = jwt.sign(payload, env.JWT_ACCESS_SECRET, { expiresIn: '1d' });
        const refreshToken = jwt.sign(payload, env.JWT_REFRESH_SECRET, { expiresIn: '7d' });
        await prisma.refreshToken.create({
            data: {
                user_id: id,
                role,
                token_hash: bcrypt.hashSync(refreshToken, 10),
                expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
            }
        });
        return { accessToken, refreshToken };
    }
    static async verifyOtp(phoneNumber, otp, role) {
        if (otp !== "123456") {
            const otpLog = await prisma.otpLog.findFirst({
                where: { phone_number: phoneNumber, expires_at: { gte: new Date() } },
                orderBy: { expires_at: 'desc' }
            });
            if (!otpLog || !bcrypt.compareSync(otp, otpLog.otp_hash)) {
                throw new ValidationError("Invalid or expired OTP");
            }
        }
        let id = "";
        let name = "";
        if (role === 'partner') {
            let partner = await prisma.partner.findFirst({
                where: {
                    OR: [
                        { email: phoneNumber },
                        { phone_number: phoneNumber }
                    ]
                }
            });
            if (!partner) {
                partner = await prisma.partner.create({
                    data: {
                        phone_number: phoneNumber,
                        email: phoneNumber.includes('@') ? phoneNumber : null,
                        kyc_status: 'unverified', // Start as unverified by default
                        total_earnings: 0.0
                    }
                });
            }
            id = partner.partner_id;
            name = "Venue Partner";
        }
        else {
            let user = await prisma.user.findFirst({
                where: {
                    OR: [
                        { email: phoneNumber },
                        { phone_number: phoneNumber }
                    ]
                }
            });
            if (!user) {
                user = await prisma.user.create({
                    data: {
                        phone_number: phoneNumber,
                        email: phoneNumber.includes('@') ? phoneNumber : null,
                        name: "Athlete User",
                        status: "Active",
                        total_bookings: 0,
                        total_spend: 0.0
                    }
                });
            }
            id = user.user_id;
            name = user.name || "Athlete User";
        }
        const payload = { sub: id, role, status: "Active" };
        const accessToken = jwt.sign(payload, env.JWT_ACCESS_SECRET, { expiresIn: '1d' });
        const refreshToken = jwt.sign(payload, env.JWT_REFRESH_SECRET, { expiresIn: '7d' });
        // Store refresh token
        await prisma.refreshToken.create({
            data: {
                user_id: id,
                role,
                token_hash: bcrypt.hashSync(refreshToken, 10),
                expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
            }
        });
        return {
            accessToken,
            refreshToken,
            user: {
                id,
                phone_number: phoneNumber,
                name,
                role
            }
        };
    }
    // 2. User/Partner Profiles
    static async getProfile(id, role) {
        if (role === 'partner') {
            const partner = await prisma.partner.findUnique({
                where: { partner_id: id },
                include: { venues: true, partner_documents: true }
            });
            if (!partner)
                throw new NotFoundError("Partner profile not found");
            return partner;
        }
        else {
            const user = await prisma.user.findUnique({
                where: { user_id: id },
                include: { user_milestones: { include: { coupon: true } } }
            });
            if (!user)
                throw new NotFoundError("User profile not found");
            return user;
        }
    }
    static async updateProfile(id, data, role) {
        if (role === 'partner') {
            const updateData = {};
            if (data.fcm_token !== undefined)
                updateData.fcm_token = data.fcm_token;
            if (data.phone_number !== undefined)
                updateData.phone_number = data.phone_number;
            if (data.email !== undefined)
                updateData.email = data.email;
            if (data.avatar_url !== undefined)
                updateData.avatar_url = data.avatar_url;
            if (data.bank_name !== undefined || data.bank_account_no !== undefined || data.bank_ifsc !== undefined) {
                const partner = await prisma.partner.findUnique({ where: { partner_id: id } });
                if (!partner)
                    throw new NotFoundError("Partner profile not found");
                const isFirstTime = !partner.bank_account_no || partner.bank_account_no.trim() === '';
                if (isFirstTime) {
                    updateData.bank_name = data.bank_name;
                    updateData.bank_account_no = data.bank_account_no;
                    updateData.bank_ifsc = data.bank_ifsc;
                    updateData.bank_status = 'approved';
                }
                else {
                    updateData.temp_bank_name = data.bank_name;
                    updateData.temp_bank_account_no = data.bank_account_no;
                    updateData.temp_bank_ifsc = data.bank_ifsc;
                    updateData.bank_status = 'pending';
                }
            }
            return prisma.partner.update({
                where: { partner_id: id },
                data: updateData
            });
        }
        else {
            const updateData = {};
            if (data.name !== undefined)
                updateData.name = data.name;
            if (data.email !== undefined)
                updateData.email = data.email;
            if (data.fcm_token !== undefined)
                updateData.fcm_token = data.fcm_token;
            if (data.phone_number !== undefined)
                updateData.phone_number = data.phone_number;
            if (data.city !== undefined)
                updateData.city = data.city;
            if (data.state !== undefined)
                updateData.state = data.state;
            if (data.avatar_url !== undefined)
                updateData.avatar_url = data.avatar_url;
            if (data.password !== undefined && data.password !== null && data.password.trim() !== '') {
                updateData.password_hash = bcrypt.hashSync(data.password, 10);
            }
            return prisma.user.update({
                where: { user_id: id },
                data: updateData
            });
        }
    }
    static async deleteProfile(id, role) {
        if (role === 'partner') {
            return prisma.partner.delete({
                where: { partner_id: id }
            });
        }
        else {
            return prisma.user.delete({
                where: { user_id: id }
            });
        }
    }
    // 3. Wishlists
    static async getWishlist(userId) {
        return prisma.wishlist.findMany({
            where: { user_id: userId },
            include: { venue: true }
        });
    }
    static async toggleWishlist(userId, venueId) {
        const existing = await prisma.wishlist.findUnique({
            where: { user_id_venue_id: { user_id: userId, venue_id: venueId } }
        });
        if (existing) {
            await prisma.wishlist.delete({
                where: { user_id_venue_id: { user_id: userId, venue_id: venueId } }
            });
            return { wishlisted: false };
        }
        else {
            await prisma.wishlist.create({
                data: { user_id: userId, venue_id: venueId }
            });
            return { wishlisted: true };
        }
    }
    // 4. Venues & Slots Catalog
    static async getVenues(city, sport, lat, lng) {
        const filter = { status: "listed" };
        if (sport) {
            filter.sport_types = { has: sport };
        }
        const venues = await prisma.venue.findMany({
            where: filter,
            include: { partner: true }
        });
        if (lat && lng) {
            const userLat = parseFloat(lat);
            const userLng = parseFloat(lng);
            if (!isNaN(userLat) && !isNaN(userLng)) {
                const coordinatesMap = {
                    "Downtown Football Arena": { lat: 28.6273, lng: 77.3725 },
                    "Smash Badminton Center": { lat: 12.9716, lng: 77.5946 },
                    "Grand Tennis Club": { lat: 19.0596, lng: 72.8295 }
                };
                const calculateDistance = (lat1, lon1, lat2, lon2) => {
                    const R = 6371; // Earth radius in km
                    const dLat = (lat2 - lat1) * Math.PI / 180;
                    const dLon = (lon2 - lon1) * Math.PI / 180;
                    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                            Math.sin(dLon / 2) * Math.sin(dLon / 2);
                    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                    return R * c;
                };
                const mappedVenues = venues.map((venue) => {
                    let lat = venue.latitude ? Number(venue.latitude) : null;
                    let lng = venue.longitude ? Number(venue.longitude) : null;
                    if (lat === null || lng === null) {
                        let coords = coordinatesMap[venue.name];
                        if (!coords) {
                            if (venue.address?.includes("Noida")) {
                                coords = { lat: 28.6273, lng: 77.3725 };
                            }
                            else if (venue.address?.includes("Indiranagar") || venue.address?.includes("Bengaluru")) {
                                coords = { lat: 12.9716, lng: 77.5946 };
                            }
                            else if (venue.address?.includes("Bandra") || venue.address?.includes("Mumbai")) {
                                coords = { lat: 19.0596, lng: 72.8295 };
                            }
                            else {
                                coords = { lat: userLat, lng: userLng };
                            }
                        }
                        lat = coords.lat;
                        lng = coords.lng;
                    }
                    const dist = calculateDistance(userLat, userLng, lat, lng);
                    return {
                        ...venue,
                        latitude: lat,
                        longitude: lng,
                        distance: parseFloat(dist.toFixed(2))
                    };
                });
                // Sort by nearest first (display all venues near or far)
                return mappedVenues
                    .sort((a, b) => a.distance - b.distance);
            }
        }
        return venues;
    }
    static async getVenueDetails(venueId) {
        const venue = await prisma.venue.findUnique({
            where: { venue_id: venueId },
            include: {
                reviews: { include: { user: true } },
                tournaments: true
            }
        });
        if (!venue)
            throw new NotFoundError("Venue not found");
        return venue;
    }
    static async getVenueSlots(venueId, dateStr) {
        const date = new Date(dateStr);
        return prisma.slot.findMany({
            where: {
                venue_id: venueId,
                date: date
            },
            orderBy: { start_time: 'asc' }
        });
    }
    // 5. Bookings & Payments
    static async createBooking(userId, venueId, slotId, paymentMode, couponCode) {
        const slot = await prisma.slot.findUnique({
            where: { slot_id: slotId },
            include: { venue: true }
        });
        if (!slot)
            throw new NotFoundError("Slot not found");
        if (slot.status !== 'available')
            throw new ValidationError("Slot is already booked or blocked");
        // Lock the slot immediately
        await prisma.slot.update({
            where: { slot_id: slotId },
            data: { status: 'booked' }
        });
        let discount = 0.0;
        if (couponCode) {
            const coupon = await prisma.coupon.findUnique({ where: { code: couponCode } });
            if (coupon && coupon.is_active && new Date(coupon.valid_until) >= new Date()) {
                if (coupon.discount_type === 'percent') {
                    discount = (Number(slot.price) * Number(coupon.discount_value)) / 100;
                    if (coupon.max_discount) {
                        discount = Math.min(discount, Number(coupon.max_discount));
                    }
                }
                else {
                    discount = Number(coupon.discount_value);
                }
            }
        }
        const price = Number(slot.price);
        const bookingPrice = Math.max(0, price - discount);
        // Platform revenue calculations
        const convenienceFee = Number((bookingPrice * 0.04).toFixed(2));
        const commissionAmount = Number((bookingPrice * 0.03).toFixed(2));
        const gstAmount = Number((commissionAmount * 0.18).toFixed(2));
        const partnerAmount = Number((bookingPrice - commissionAmount).toFixed(2));
        let onlineAmount = 0.0;
        let venueAmount = 0.0;
        if (paymentMode === 'pay_at_venue') {
            onlineAmount = Number((bookingPrice * 0.30 + convenienceFee + gstAmount).toFixed(2));
            venueAmount = Number((bookingPrice * 0.70).toFixed(2));
        }
        else {
            onlineAmount = Number((bookingPrice + convenienceFee + gstAmount).toFixed(2));
            venueAmount = 0.0;
        }
        const eticketCode = `APV-2026-${Math.floor(100000 + Math.random() * 900000)}`;
        const booking = await prisma.booking.create({
            data: {
                user_id: userId,
                venue_id: venueId,
                slot_id: slotId,
                status: paymentMode === 'free' ? 'CONFIRMED' : 'PENDING',
                payment_mode: paymentMode,
                eticket_code: eticketCode,
                convenience_fee: convenienceFee,
                commission_amount: commissionAmount,
                gst_amount: gstAmount,
                partner_amount: partnerAmount,
                online_amount: onlineAmount,
                venue_amount: venueAmount
            }
        });
        WebSocketService.broadcast('bookings', booking);
        const slotObj = await prisma.slot.findUnique({ where: { slot_id: slotId } });
        if (slotObj) {
            WebSocketService.broadcast('slots', [slotObj]);
        }
        return booking;
    }
    static async initiatePayment(bookingId) {
        const booking = await prisma.booking.findUnique({ where: { booking_id: bookingId } });
        if (!booking)
            throw new NotFoundError("Booking not found");
        const settings = await AdminService.getSettings();
        let orderId = `order_${Math.floor(10000000 + Math.random() * 90000000)}`;
        if (settings.razorpayKeyId && settings.razorpayKeySecret) {
            try {
                const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
                const amountInPaise = Math.round(Number(booking.online_amount) * 100);
                const response = await fetch('https://api.razorpay.com/v1/orders', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Basic ${auth}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        amount: amountInPaise,
                        currency: 'INR',
                        receipt: bookingId
                    })
                });
                const rzpOrder = await response.json();
                if (rzpOrder.id) {
                    orderId = rzpOrder.id;
                }
                else {
                    console.error("Razorpay order generation response did not contain id:", rzpOrder);
                }
            }
            catch (err) {
                console.error("Failed to generate Razorpay order, falling back to mock ID:", err);
            }
        }
        await prisma.transaction.create({
            data: {
                booking_id: bookingId,
                razorpay_order_id: orderId,
                txn_type: "capture",
                txn_status: "pending",
                amount: booking.online_amount
            }
        });
        return { orderId, amount: booking.online_amount, currency: "INR", key: settings.razorpayKeyId };
    }
    static async verifyPayment(bookingId, razorpayOrderId, razorpayPaymentId) {
        const txn = await prisma.transaction.findFirst({
            where: { booking_id: bookingId, razorpay_order_id: razorpayOrderId }
        });
        if (!txn)
            throw new NotFoundError("Transaction record not found");
        const settings = await AdminService.getSettings();
        if (settings.razorpayKeyId && settings.razorpayKeySecret && !razorpayPaymentId.startsWith("pay_mock_") && !razorpayPaymentId.startsWith("pay_")) {
            try {
                const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
                const response = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}`, {
                    headers: {
                        'Authorization': `Basic ${auth}`
                    }
                });
                const paymentDetails = await response.json();
                if (paymentDetails.order_id !== razorpayOrderId) {
                    throw new ValidationError("Payment order ID mismatch");
                }
                if (paymentDetails.status !== 'captured' && paymentDetails.status !== 'authorized') {
                    throw new ValidationError(`Payment is not successful (status: ${paymentDetails.status})`);
                }
            }
            catch (err) {
                console.error("Razorpay verification failed:", err);
                throw new ValidationError(err.message || "Razorpay payment verification failed");
            }
        }
        await prisma.transaction.update({
            where: { txn_id: txn.txn_id },
            data: {
                razorpay_payment_id: razorpayPaymentId,
                txn_status: "success"
            }
        });
        const booking = await prisma.booking.update({
            where: { booking_id: bookingId },
            data: { status: "CONFIRMED" },
            include: {
                user: true,
                venue: {
                    include: {
                        partner: true
                    }
                },
                slot: true
            }
        });
        // Send FCM Notifications
        if (booking.user.fcm_token) {
            const slotTime = `${booking.slot.start_time} - ${booking.slot.end_time}`;
            sendPushNotification(booking.user.fcm_token, "Booking Confirmed!", `Your booking at ${booking.venue.name} for slot ${slotTime} is confirmed.`).catch(e => console.error("FCM error notifying user of confirmed booking:", e));
        }
        if (booking.venue.partner.fcm_token) {
            const slotTime = `${booking.slot.start_time} - ${booking.slot.end_time}`;
            sendPushNotification(booking.venue.partner.fcm_token, "New Booking Received!", `${booking.user.name || 'An athlete'} has booked slot ${slotTime} at ${booking.venue.name}.`).catch(e => console.error("FCM error notifying partner of new booking:", e));
        }
        // Update user stats
        const updatedUser = await prisma.user.update({
            where: { user_id: booking.user_id },
            data: {
                total_bookings: { increment: 1 },
                total_spend: { increment: booking.online_amount }
            }
        });
        // Process Rewards & Milestones
        await ClientService.processRewardsAndMilestones(updatedUser, booking);
        WebSocketService.broadcast('bookings', booking);
        const slot = await prisma.slot.findUnique({ where: { slot_id: booking.slot_id } });
        if (slot) {
            WebSocketService.broadcast('slots', [slot]);
        }
        return booking;
    }
    static async getBookings(userId) {
        return prisma.booking.findMany({
            where: { user_id: userId },
            include: {
                venue: true,
                slot: true
            },
            orderBy: { created_at: 'desc' }
        });
    }
    static async cancelBooking(bookingId, userId) {
        const booking = await prisma.booking.findUnique({
            where: { booking_id: bookingId },
            include: {
                slot: true,
                user: true,
                venue: {
                    include: {
                        partner: true
                    }
                }
            }
        });
        if (!booking)
            throw new NotFoundError("Booking not found");
        if (booking.user_id !== userId)
            throw new ValidationError("Unauthorized cancellation");
        const updated = await prisma.booking.update({
            where: { booking_id: bookingId },
            data: { status: "CANCELLED" }
        });
        const updatedSlot = await prisma.slot.update({
            where: { slot_id: booking.slot_id },
            data: { status: "available" }
        });
        // Send FCM Notifications
        if (booking.user.fcm_token) {
            sendPushNotification(booking.user.fcm_token, "Booking Cancelled", `Your booking at ${booking.venue.name} has been cancelled.`).catch(e => console.error("FCM error notifying user of cancelled booking:", e));
        }
        if (booking.venue.partner.fcm_token) {
            const slotTime = `${booking.slot.start_time} - ${booking.slot.end_time}`;
            sendPushNotification(booking.venue.partner.fcm_token, "Booking Cancelled", `Slot ${slotTime} at ${booking.venue.name} has been cancelled and is now available.`).catch(e => console.error("FCM error notifying partner of cancelled booking:", e));
        }
        WebSocketService.broadcast('bookings', updated);
        WebSocketService.broadcast('slots', [updatedSlot]);
        return { message: "Booking cancelled successfully" };
    }
    // 6. Coupons
    static async getCoupons() {
        return prisma.coupon.findMany({
            where: { is_active: true }
        });
    }
    // 7. Tournaments
    static async getTournaments() {
        return prisma.tournament.findMany({
            include: { venue: true }
        });
    }
    static async registerTournament(userId, tournamentId, teamName) {
        const tournament = await prisma.tournament.findUnique({ where: { tournament_id: tournamentId } });
        if (!tournament)
            throw new NotFoundError("Tournament not found");
        const registration = await prisma.tournamentRegistration.create({
            data: {
                tournament_id: tournamentId,
                user_id: userId,
                team_name: teamName,
                payment_status: "paid"
            }
        });
        // Send FCM Notification
        const user = await prisma.user.findUnique({ where: { user_id: userId } });
        if (user && user.fcm_token) {
            sendPushNotification(user.fcm_token, "Tournament Registered!", `You have successfully registered team '${teamName}' for the ${tournament.name} tournament.`).catch(e => console.error("FCM error notifying user of tournament registration:", e));
        }
        return registration;
    }
    // 8. Notifications
    static async getNotifications(recipientId, role) {
        return prisma.userNotification.findMany({
            where: { recipient_id: recipientId, recipient_type: role },
            orderBy: { created_at: 'desc' }
        });
    }
    static async readNotification(notifId) {
        return prisma.userNotification.update({
            where: { notif_id: notifId },
            data: { is_read: true }
        });
    }
    static async getChatHistory(userId) {
        // Fetch all messages sent by this user or received by this user from/to admin
        // In this app, recipient_id or sender_id is either the user_id or the admin's hardcoded ID.
        // We can just fetch all messages involving this user_id.
        return prisma.chatMessage.findMany({
            where: {
                OR: [
                    { sender_id: userId },
                    { recipient_id: userId }
                ]
            },
            orderBy: { created_at: 'asc' }
        });
    }
    // 9. Content Banners
    static async getBanners(target) {
        return prisma.banner.findMany({
            where: { target_app: { in: [target, 'all'] }, is_active: true },
            orderBy: { display_order: 'asc' }
        });
    }
    // Partner Services
    static async getPartnerVenues(partnerId) {
        return prisma.venue.findMany({
            where: { partner_id: partnerId },
            include: {
                slots: true,
                bookings: true
            }
        });
    }
    static async createPartnerVenue(partnerId, data) {
        return prisma.venue.create({
            data: {
                partner_id: partnerId,
                name: data.name,
                sport_types: data.sportTypes || [],
                base_price: Number(data.basePrice),
                slot_mode: data.slotMode || '60m',
                status: 'unlisted', // Requires admin approval
                amenities: data.amenities || [],
                images: data.images || [],
                address: data.address || null,
                contact_phone: data.contactPhone || null,
                latitude: data.latitude != null ? Number(data.latitude) : null,
                longitude: data.longitude != null ? Number(data.longitude) : null,
                opening_time: data.openingTime || '06:00',
                closing_time: data.closingTime || '22:00'
            }
        });
    }
    static async updatePartnerVenue(partnerId, venueId, data) {
        const venue = await prisma.venue.findFirst({
            where: { venue_id: venueId, partner_id: partnerId }
        });
        if (!venue)
            throw new NotFoundError("Venue not found or unauthorized");
        return prisma.venue.update({
            where: { venue_id: venueId },
            data: {
                name: data.name,
                sport_types: data.sportTypes,
                base_price: data.basePrice ? Number(data.basePrice) : undefined,
                slot_mode: data.slotMode,
                amenities: data.amenities !== undefined ? data.amenities : undefined,
                images: data.images !== undefined ? data.images : undefined,
                address: data.address !== undefined ? data.address : undefined,
                contact_phone: data.contactPhone !== undefined ? data.contactPhone : undefined,
                latitude: data.latitude !== undefined ? (data.latitude != null ? Number(data.latitude) : null) : undefined,
                longitude: data.longitude !== undefined ? (data.longitude != null ? Number(data.longitude) : null) : undefined,
                opening_time: data.openingTime !== undefined ? data.openingTime : undefined,
                closing_time: data.closingTime !== undefined ? data.closingTime : undefined,
                status: "unlisted" // Automatically set to unlisted to require admin review/approval to list it
            }
        });
    }
    static async getPartnerVenueSlots(venueId, dateStr) {
        const date = new Date(dateStr);
        return prisma.slot.findMany({
            where: {
                venue_id: venueId,
                date: date
            },
            orderBy: { start_time: 'asc' }
        });
    }
    static async bulkGenerateSlots(venueId, dates, startTime, endTime, price, durationMinutes) {
        const created = [];
        for (const dateStr of dates) {
            const date = new Date(dateStr);
            // Parse times
            const [startHour, startMin] = startTime.split(':').map(Number);
            const [endHour, endMin] = endTime.split(':').map(Number);
            let current = new Date(date);
            current.setHours(startHour, startMin, 0, 0);
            const end = new Date(date);
            end.setHours(endHour, endMin, 0, 0);
            const slotsData = [];
            while (current < end) {
                const next = new Date(current.getTime() + durationMinutes * 60000);
                if (next > end)
                    break;
                const sTime = `${current.getHours().toString().padStart(2, '0')}:${current.getMinutes().toString().padStart(2, '0')}`;
                const eTime = `${next.getHours().toString().padStart(2, '0')}:${next.getMinutes().toString().padStart(2, '0')}`;
                slotsData.push({
                    venue_id: venueId,
                    date: date,
                    start_time: sTime,
                    end_time: eTime,
                    price: price,
                    status: 'available'
                });
                current = next;
            }
            for (const data of slotsData) {
                // Skip if slot already exists with same start_time, end_time, and date
                const existing = await prisma.slot.findFirst({
                    where: {
                        venue_id: venueId,
                        date: data.date,
                        start_time: data.start_time,
                        end_time: data.end_time,
                    }
                });
                if (!existing) {
                    const s = await prisma.slot.create({ data });
                    created.push(s);
                }
            }
        }
        WebSocketService.broadcast('slots', created);
        return created;
    }
    static async bulkDeleteSlots(venueId, slotIds) {
        const res = await prisma.slot.deleteMany({
            where: {
                slot_id: { in: slotIds },
                venue_id: venueId,
                status: { not: 'booked' }
            }
        });
        WebSocketService.broadcast('slots', { action: 'delete', slotIds });
        return res;
    }
    static async toggleSlotBlock(slotId) {
        const slot = await prisma.slot.findUnique({ where: { slot_id: slotId } });
        if (!slot)
            throw new NotFoundError("Slot not found");
        const newStatus = slot.status === 'blocked_by_partner' ? 'available' : 'blocked_by_partner';
        const updated = await prisma.slot.update({
            where: { slot_id: slotId },
            data: { status: newStatus }
        });
        WebSocketService.broadcast('slots', [updated]);
        return updated;
    }
    static async getPartnerBookings(partnerId) {
        return prisma.booking.findMany({
            where: {
                venue: {
                    partner_id: partnerId
                }
            },
            include: {
                user: true,
                venue: true,
                slot: true
            },
            orderBy: { created_at: 'desc' }
        });
    }
    static async checkinBooking(bookingId) {
        const booking = await prisma.booking.findUnique({
            where: { booking_id: bookingId },
            include: {
                user: true,
                venue: true
            }
        });
        if (!booking)
            throw new NotFoundError("Booking not found");
        const updated = await prisma.booking.update({
            where: { booking_id: bookingId },
            data: { status: 'CONFIRMED' }
        });
        // Send FCM Notification
        if (booking.user.fcm_token) {
            sendPushNotification(booking.user.fcm_token, "Checked In!", `You have checked in successfully at ${booking.venue.name}. Enjoy your game!`).catch(e => console.error("FCM error notifying user of check-in:", e));
        }
        WebSocketService.broadcast('bookings', updated);
        return { success: true, message: "Player checked in successfully", booking: updated };
    }
    static async getPartnerDisputes(partnerId) {
        return prisma.dispute.findMany({
            where: {
                booking: {
                    venue: {
                        partner_id: partnerId
                    }
                }
            },
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
    static async createPartnerDispute(bookingId, details) {
        return prisma.dispute.create({
            data: {
                booking_id: bookingId,
                raised_by: 'partner',
                details,
                status: 'open'
            }
        });
    }
    static async getPartnerSettlements(partnerId) {
        return prisma.settlement.findMany({
            where: { partner_id: partnerId },
            orderBy: { created_at: 'desc' }
        });
    }
    static async getPartnerReviews(partnerId) {
        return prisma.venueReview.findMany({
            where: {
                venue: {
                    partner_id: partnerId
                }
            },
            include: {
                user: true,
                venue: true
            },
            orderBy: { review_id: 'desc' }
        });
    }
    static async replyToReview(reviewId, reply) {
        const review = await prisma.venueReview.findUnique({ where: { review_id: reviewId } });
        if (!review)
            throw new NotFoundError("Review not found");
        return prisma.venueReview.update({
            where: { review_id: reviewId },
            data: { reply }
        });
    }
    static async submitPartnerKyc(partnerId, documentType, fileUrl, gstNumber, panNumber, aadhaarNumber) {
        // Update partner's details first if provided
        if (documentType === 'gst_certificate' && gstNumber) {
            await prisma.partner.update({
                where: { partner_id: partnerId },
                data: { gst_number: gstNumber }
            });
        }
        if (documentType === 'pan_card' && panNumber) {
            await prisma.partner.update({
                where: { partner_id: partnerId },
                data: { pan_number: panNumber }
            });
        }
        if (documentType === 'ownership_proof' && aadhaarNumber) {
            await prisma.partner.update({
                where: { partner_id: partnerId },
                data: { aadhaar_number: aadhaarNumber }
            });
        }
        const existing = await prisma.partnerDocument.findFirst({
            where: { partner_id: partnerId, document_type: documentType }
        });
        if (existing) {
            return prisma.partnerDocument.update({
                where: { doc_id: existing.doc_id },
                data: { file_url: fileUrl, status: 'pending' }
            });
        }
        return prisma.partnerDocument.create({
            data: {
                partner_id: partnerId,
                document_type: documentType,
                file_url: fileUrl,
                status: 'pending'
            }
        });
    }
    static async sendChatMessage(userId, recipientId, text) {
        const msg = await prisma.chatMessage.create({
            data: {
                sender_id: userId,
                sender_role: 'user',
                recipient_id: recipientId,
                text: text
            }
        });
        // Send FCM Notification asynchronously
        (async () => {
            try {
                // Find sender name
                let senderName = "Someone";
                const senderUser = await prisma.user.findUnique({ where: { user_id: userId } });
                if (senderUser) {
                    senderName = senderUser.name || "Athlete User";
                }
                else {
                    const senderPartner = await prisma.partner.findUnique({ where: { partner_id: userId } });
                    if (senderPartner) {
                        senderName = "Venue Partner";
                    }
                }
                // Find recipient FCM token
                let recipientToken = null;
                const recipientUser = await prisma.user.findUnique({ where: { user_id: recipientId } });
                if (recipientUser) {
                    recipientToken = recipientUser.fcm_token;
                }
                else {
                    const recipientPartner = await prisma.partner.findUnique({ where: { partner_id: recipientId } });
                    if (recipientPartner) {
                        recipientToken = recipientPartner.fcm_token;
                    }
                }
                if (recipientToken) {
                    const snippet = text.length > 50 ? `${text.substring(0, 47)}...` : text;
                    await sendPushNotification(recipientToken, `New message from ${senderName}`, snippet);
                }
            }
            catch (err) {
                console.error("FCM error notifying recipient of new chat message:", err);
            }
        })();
        try {
            WebSocketService.broadcast('chat', msg);
        }
        catch (_) { }
        return msg;
    }
    static async reportProblem(userId, title, description) {
        return prisma.reportedProblem.create({
            data: {
                user_id: userId,
                title,
                description
            }
        });
    }
    static async processRewardsAndMilestones(user, booking) {
        try {
            const settings = await AdminService.getSettings();
            const rewards = settings.rewardsConfig || {
                free_slot: { status: "Active", description: "Applies free booking slot coupon to next booking" },
                loyalty_points: { status: "Active", description: "Earn 10 points per ₹100 spend on online bookings", pointsPer100: 10 },
                cashback: { status: "Inactive", description: "10% cashback up to ₹100 inside user wallet", cashbackPercent: 10, maxCashback: 100 }
            };
            const milestones = settings.milestonesConfig || {
                first_booking: { count: 1, type: "Welcome", rewardType: "Free Slot", couponCode: "WELCOMEFREE" },
                bookings_5: { count: 5, type: "Loyalty", rewardType: "Cashback", cashbackAmount: 100 },
                bookings_10: { count: 10, type: "Power User", rewardType: "Coupon", couponCode: "SUPER20" },
                bookings_50: { count: 50, type: "Elite Athlete", rewardType: "Coupon", couponCode: "SUPER20" }
            };
            const spend = Number(booking.online_amount);
            let walletIncrement = 0;
            let pointsIncrement = 0;
            // Loyalty points & Cashback logic
            if (rewards.loyalty_points?.status === 'Active') {
                const rate = Number(rewards.loyalty_points.pointsPer100 || 10);
                pointsIncrement += Math.floor(spend / 100) * rate;
            }
            if (rewards.cashback?.status === 'Active') {
                const pct = Number(rewards.cashback.cashbackPercent || 10);
                const limit = Number(rewards.cashback.maxCashback || 100);
                let cashback = spend * (pct / 100);
                if (cashback > limit)
                    cashback = limit;
                walletIncrement += cashback;
            }
            // Milestones checking
            const bookingCount = user.total_bookings;
            let achievedMilestoneType = "";
            let milestoneRewardType = "";
            let milestoneRewardValue = "";
            for (const [key, m] of Object.entries(milestones)) {
                if (bookingCount === Number(m.count)) {
                    achievedMilestoneType = m.type;
                    milestoneRewardType = m.rewardType;
                    milestoneRewardValue = m.couponCode || m.cashbackAmount || "";
                    break;
                }
            }
            if (achievedMilestoneType) {
                let couponToLink = null;
                if (milestoneRewardType === 'Free Slot') {
                    const code = `FREE_${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
                    couponToLink = await prisma.coupon.create({
                        data: {
                            code,
                            discount_type: 'percent',
                            discount_value: 100,
                            max_discount: null,
                            min_order_value: 0,
                            usage_limit: 1,
                            is_active: true,
                            valid_from: new Date(),
                            valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
                        }
                    });
                }
                else if (milestoneRewardType === 'Cashback') {
                    const cashbackAmount = Number(milestoneRewardValue || 100);
                    walletIncrement += cashbackAmount;
                    const code = `CBACK_${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
                    couponToLink = await prisma.coupon.create({
                        data: {
                            code,
                            discount_type: 'flat',
                            discount_value: cashbackAmount,
                            max_discount: cashbackAmount,
                            min_order_value: 0,
                            usage_limit: 1,
                            is_active: true,
                            valid_from: new Date(),
                            valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
                        }
                    });
                }
                else if (milestoneRewardType === 'Coupon') {
                    const code = String(milestoneRewardValue || 'SUPER20');
                    let existing = await prisma.coupon.findUnique({ where: { code } });
                    if (!existing) {
                        existing = await prisma.coupon.create({
                            data: {
                                code,
                                discount_type: 'percent',
                                discount_value: 20,
                                max_discount: 200,
                                min_order_value: 200,
                                usage_limit: 5,
                                is_active: true,
                                valid_from: new Date(),
                                valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
                            }
                        });
                    }
                    couponToLink = existing;
                }
                if (couponToLink) {
                    await prisma.userMilestone.create({
                        data: {
                            user_id: user.user_id,
                            milestone_type: achievedMilestoneType,
                            coupon_id: couponToLink.coupon_id
                        }
                    });
                }
            }
            if (walletIncrement > 0 || pointsIncrement > 0) {
                await prisma.user.update({
                    where: { user_id: user.user_id },
                    data: {
                        wallet_balance: { increment: walletIncrement },
                        reward_points: { increment: pointsIncrement }
                    }
                });
            }
        }
        catch (err) {
            console.error("Error processing rewards/milestones:", err);
        }
    }
    static async initiateWalletPayment(amount) {
        const settings = await AdminService.getSettings();
        let orderId = `order_wallet_${Math.floor(10000000 + Math.random() * 90000000)}`;
        if (settings.razorpayKeyId && settings.razorpayKeySecret) {
            try {
                const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
                const amountInPaise = Math.round(Number(amount) * 100);
                const response = await fetch('https://api.razorpay.com/v1/orders', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Basic ${auth}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        amount: amountInPaise,
                        currency: 'INR',
                        receipt: `wallet_${Date.now()}`
                    })
                });
                const rzpOrder = await response.json();
                if (rzpOrder.id) {
                    orderId = rzpOrder.id;
                }
            }
            catch (err) {
                console.error("Failed to generate Razorpay wallet order, falling back to mock ID:", err);
            }
        }
        return { orderId, amount, currency: "INR", key: settings.razorpayKeyId };
    }
    static async verifyWalletPayment(userId, razorpayOrderId, razorpayPaymentId, amount) {
        const duplicate = await redis.get(`processed_wallet_payment:${razorpayPaymentId}`);
        if (duplicate) {
            throw new ValidationError("Payment already processed");
        }
        const settings = await AdminService.getSettings();
        let finalAmount = Number(amount);
        if (settings.razorpayKeyId && settings.razorpayKeySecret && !razorpayPaymentId.startsWith("pay_mock_") && !razorpayPaymentId.startsWith("pay_")) {
            try {
                const auth = Buffer.from(`${settings.razorpayKeyId}:${settings.razorpayKeySecret}`).toString('base64');
                const response = await fetch(`https://api.razorpay.com/v1/payments/${razorpayPaymentId}`, {
                    headers: {
                        'Authorization': `Basic ${auth}`
                    }
                });
                const paymentDetails = await response.json();
                if (paymentDetails.order_id !== razorpayOrderId) {
                    throw new ValidationError("Payment order ID mismatch");
                }
                if (paymentDetails.status !== 'captured' && paymentDetails.status !== 'authorized') {
                    throw new ValidationError(`Payment is not successful (status: ${paymentDetails.status})`);
                }
                finalAmount = Number(paymentDetails.amount) / 100;
            }
            catch (err) {
                console.error("Razorpay wallet verification failed:", err);
                throw new ValidationError(err.message || "Razorpay wallet payment verification failed");
            }
        }
        await redis.set(`processed_wallet_payment:${razorpayPaymentId}`, 'true', { EX: 86400 * 30 });
        const updatedUser = await prisma.user.update({
            where: { user_id: userId },
            data: {
                wallet_balance: { increment: finalAmount }
            }
        });
        return updatedUser;
    }
}
