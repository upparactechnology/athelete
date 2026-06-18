# Product Requirements Document (PRD): Athlete's POV (APOV)

## 1. Product Goals & Objectives
The objective of Athlete's POV (APOV) is to build a high-performance, double-sided marketplace for sports facility bookings in India. The product simplifies the process of finding and booking turf pitches, badminton courts, and other sports venues, while providing facility owners with slot management, dynamic surge pricing, and settlement automation.

### Core Goals:
- **Zero Double-Bookings**: Protect slot availability using real-time concurrency locking.
- **Flexible Checkout options**: Allow users to pay fully online or split payment with a secure 30% online deposit (Pay-at-Venue).
- **Gamified Engagement**: Incentivize repeat bookings through milestone rewards.
- **Admin Control**: Provide operators with compliance, auditing, dispute resolution, and marketing tools.

---

## 2. Target Audience & Stakeholders
- **Casual Athletes / Players**: Need to find available slots, compare prices, apply discounts, get check-in tickets, and play.
- **Venue Owners / Partners**: Need to onboard quickly, verify business details, schedule slots, block slots for offline tournaments, and receive payouts.
- **Platform Admins**: Need to oversee verification queues, audit chats/reviews, resolve payment disputes, edit commission structures, and push broadcasts.

---

## 3. Functional Requirements

### A. Authentication & Onboarding
- **Phone-OTP Login**: Primary login mechanism for users and partners. OTPs are valid for 5 minutes and rate-limited.
- **OAuth Social Login**: Google and Apple authentication integrations (Apple blocked in production, dev-only).
- **KYC Onboarding for Partners**: Partners must submit business records (GST Certificate, PAN Card, etc.) before creating venues.

### B. Venue & Slot Management
- **8-Step Setup Wizard**: A multi-step form guiding partners through basic details, sports types, hours, pricing, and pictures.
- **Redis Concurrency Lock**: When a user selects a slot, the system locks it in Redis for 15 seconds. If the payment process is not finalized or does not succeed, the lock automatically expires, releasing the slot.
- **Dynamic Pricing (Demand Tags)**: Admins apply modifiers (e.g. `peak_hours` tag) that increase slot prices by 50% automatically.
- **Manual Slot Blocking**: Partners can block specific slot cells (represented as gray striped blocks) for offline walk-ins or maintenance.

### C. Checkout & Booking Lifecycle
- **Two-Step Checkout**: Booking is created in `PENDING` state, payment is finalized on the client, and booking is marked `CONFIRMED` upon Razorpay payment or webhook verification.
- **Idempotency Guard**: Re-submits check Redis cache (`booking:idem:{userId}:{slotId}`) to avoid double transactions.
- **Cancellation & Refunds**: Bookings cancelled within 24 hours of creation are eligible for automated refunds.

### D. Financial Settlements
- **Commission Split**: Platform charges a 3% commission on bookings + 18% GST on that commission.
- **Pay-At-Venue Adjustments**: Online deposit is 30%; remaining 70% is cash. The 3% platform commission (calculated on the full booking amount) is tracked and deducted from the partner's online payout during weekly settlements.

### E. Loyalty & Gamification
- **Milestone Rewards**: System automatically generates coupon codes as users reach booking milestones (1st booking, 3rd booking, 3 bookings in 7 days, 10 bookings).

### F. Communication & Notifications
- **FCM Push Notifications**: Triggers alerts on bookings, cancellations, KYC updates, and admin broadcasts.
- **AI Chatbot Overlay**: In-app overlay answering venue and booking queries using context metadata.

---

## 4. Key Business Constraints & Constants
These constants are defined in `bookings.service.ts` and must remain constant:

```typescript
export const CONVENIENCE_FEE_RATE = 0.04;  // 4% Convenience fee for online card/UPI payments
export const COMMISSION_RATE = 0.03;       // 3% Platform commission rate
export const GST_RATE = 0.18;              // 18% GST applied on top of platform commission
export const PAV_ONLINE_PCT = 0.30;        // 30% Online deposit for PAV bookings
export const PAV_VENUE_PCT = 0.70;         // 70% Paid at physical turf for PAV bookings
```

---

## 5. Security & Verification
- All user passwords (Admins only) and OTP codes are hashed via bcrypt.
- Webhook endpoints require strict HMAC-SHA256 signature verification computed over the RAW request body.
- Admin endpoints require X-Admin-Role double-header verification.
