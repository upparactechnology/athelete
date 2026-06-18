# Features Reference: Athlete's POV (APOV)

This document maps all user-facing, partner-facing, and admin-facing features within the AthletePOV platform, including status descriptions.

---

## 1. Athlete / User Feature Set

### Search, Filters & Discovery
- **Location Selector**: Prompt for GPS access or manual city inputs (Delhi, Mumbai, etc.) before booking.
- **Venue Search & Filters**: Search field for turf name/address, filters for sports types (Football, Cricket, Badminton), and sorting options (Price Low-to-High, Rating).
- **Wishlist Heart Toggle**: Saves sports venues to a personal wishlist. Syncs immediately on authentication.

### Booking & Checkout
- **Date Picker Calendar**: Selecting date coordinates availability schedules.
- **Dynamic Slot Grid**: Interactive slot layout displaying state (Booked, Available, Blocked) and base price.
- **Coupon Code Form**: Form input to check, validate, and apply coupon codes from the user wallet.
- **Razorpay Checkout Modal**: Card/UPI checkout pop-up overlay for payment collection.
- **Pay at Venue (PAV) Split Toggle**: Splits booking transaction (30% online deposit / 70% cash at court).
- **E-Ticket QR Code Display**: Confirmed bookings generate a page containing a check-in ticket ID (`APV-2026-XXXXXX`) and QR graphic.

### User Account & Profile
- **OTP Login & Register**: SMS request/verify OTP flow with validation checks and countdown timer.
- **Profile Edit Form**: Updates profile attributes (DOB, Gender, Language).
- **Booking History List**: Past and upcoming bookings, status trackers, and cancellation buttons.
- **Cancellation Reason Modal**: Requests cancellation reason before slot release.
- **Refund Tracker Badges**: My Bookings items show cancellation refund statuses (`refund_initiated`, `refund_credited`).
- **Gamified Milestones (Badges)**: Unlocked badges display in the statistics page once milestone targets are reached.
- **Tournament Entry Panel**: Allows team registration and fee payments for hosted tournaments.

---

## 2. Venue Partner Feature Set

### Venue Operations
- **8-Step Setup Wizard**: Sequence of panels for details (basics, sports type, pricing, hours, photo gallery) to create turf listings.
- **Slot Scheduling Console**: Creates time intervals, slot sizes, and default prices.
- **Slot Block/Unblock Toggle**: Grid cells allow partners to block specific slots for walk-ins or maintenance.
- **E-Ticket QR Scanner**: Host-side camera scan overlay or text search to check in arriving players.
- **Review Replies Feed**: Section allowing venue hosts to write public responses to review ratings.

### Payments & Analytics
- **Today's Bookings Widget**: Panel on dashboard home listing check-ins scheduled for the day.
- **Earnings & Revenue Analytics**: Interactive charts graphing revenue trends and hourly slot demand.
- **Disputes Inbox**: Displays payment dispute filings and allows hosts to upload rebuttal statements.
- **Payout Bank Setup Form**: Forms inputting Account Number, IFSC, and UPI details for settlements.
- **KYC File Uploader**: Form to upload pan card, gst certificates, and lease papers directly to S3.
- **CSV Earnings Export**: Downloads Excel-compatible CSV reports of earnings.

---

## 3. Platform Admin Feature Set

### Operations & Auditing
- **KYC Document Queue**: Verification panel loading S3 documents in a modal, with Approve/Reject controllers.
- **Venue Approvals Panel**: Approve, Reject (with reason dialog), or Suspend controllers for turf listings.
- **Slot Reassignment Tool**: Re-assigns confirmed bookings to different slots.
- **Booking Refund Controller**: Cancels bookings and initiates Razorpay refund payments.
- **Message Compliance Monitor**: Audits user-partner chat logs for security compliance.
- **Review Moderation Panel**: Moderates and flags/hides user reviews.

### Settings & Configurations
- **Milestone Configurator**: Modifies target booking counts and coupon codes.
- **Commission Rate Editor**: Adjusts platform fee percentages globally or per partner.
- **Surge Pricing Tag Editor**: Selects slots to apply dynamic pricing/surge tags (+50% pricing).
- **Broadcast Composer Form**: Composes targeted push messages and sends them to cohorts.
- **Content Carousel Manager**: Sets homepage banners and display order.
