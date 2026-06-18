# AthletePOV UI Feature Extraction & Business Model Reconstruction Report

- **Date**: 2026-06-17
- **Source**: Extract from APOV JSX Frontend and Business Model

---

## 1. Applications Overview

The Athlete's POV (APOV) platform consists of four distinct user-facing applications:

1. **AthletePOV User App (Mobile-first Web App)**
   - **Purpose**: Enables athletes and sports enthusiasts to discover sports turfs, courts, and facilities, view real-time slot availability, reserve and pay for slots, track gamified milestones, register for local tournaments, and communicate with venue hosts.
   - **Target Audience**: General public, casual sports players, amateur athletes, and team managers.

2. **AthletePOV Partner App (Mobile-first Management Web App)**
   - **Purpose**: Allows sports venue owners and facility operators to register their businesses, upload KYC documentation, configure venue characteristics, set up playing schedules (slots) with dynamic pricing, block/unblock slots, manage bookings, view revenue/analytics, and reply to reviews.
   - **Target Audience**: Venue owners, facility managers, sports academy operators, and staff members.

3. **AthletePOV Admin Portal (Desktop Web Application)**
   - **Purpose**: Centralized administration console for platform owners. Used to approve partners and listed venues, manage disputes, verify KYC documents, configure gamified user milestones, issue promotional coupons, monitor user-partner chat logs, schedule broadcast notification campaigns, and moderate user reviews.
   - **Target Audience**: Platform operations, customer support, and system administrators.

4. **Landing Website**
   - **Purpose**: Public-facing promotional portal introducing the platform's benefits, displaying featured venues, and providing action prompts (CTAs) for users to sign up or download the app.
   - **Target Audience**: General visitors, prospective athletes, and potential venue owners.

---

## 2. UI Feature Catalog

This catalog details every UI component, interactive element, and feature extracted from the JSX source code.

### User App Features

| Feature Name | Purpose | Page Location | Status / Wiring |
| :--- | :--- | :--- | :--- |
| **Carousel Slide Banner** | Promotes active tournaments and deals | User Landing / Home Tab | Partially Implemented (Mock Carousel) |
| **Location Prompt / Selection** | Requests GPS coordinates or manual city input | Location Screen | Partially Implemented (Mock GPS/City) |
| **Venue Search & Filter** | Searches name/area, filters by sport/area, sorts by price/rating | Home Tab (main) | Partially Implemented (Mock Filters) |
| **Venue Detail Panel** | Shows photos, address, amenities list, and rating/reviews | Venue Detail Screen | Partially Implemented (Mock View) |
| **Date Picker Calendar** | Selects target booking date for scheduling slots | Venue Detail Screen | Partially Implemented (Mock Selection) |
| **Dynamic Slot Grid** | Shows slot timings, base prices, and states (Booked/Available/Unavailable) | Venue Detail Screen | Partially Implemented (Wired with SlotButton) |
| **Coupon Code Form** | Input box to apply discounts on total order price | Booking / Checkout Screen | Partially Implemented (Wired with wallet) |
| **Razorpay Payment Gateway** | Triggers card/UPI checkout popup overlay | Booking / Checkout Screen | Partially Implemented (Integration guide) |
| **Pay at Venue (PAV) Toggle** | Splits payment: 30% online deposit + 70% paid at turf | Booking / Checkout Screen | Partially Implemented (UI and API ready) |
| **QR Code E-Ticket** | Displays booking details and check-in QR code | Booking Confirmation Screen | Partially Implemented (QR Code Mock) |
| **Cancellation Modal** | Requests reason string before cancelling a slot booking | My Bookings Tab | Partially Implemented (Cancellation ready) |
| **Refund Status Badge** | Displays whether refund is credited or initiated | My Bookings Tab | Partially Implemented (Wired in Sprint 6) |
| **Wishlist Heart Toggle** | Saves venues to personal favorites list | Home Card / Detail Header | Partially Implemented (Syncs on login) |
| **Review Submission Box** | Selects stars (1-5) and enters text feedback on played venues | Venue Detail Screen | Partially Implemented (Saves locally) |
| **Gamification Milestone Badges** | Shows unlocked badges (First Booking, Hat Trick, Regular) | Statistics Screen / Profile | Partially Implemented (Mock badges) |
| **Tournament Registration Modal** | Registers teams for tournaments with fee checkout | Tournaments Tab | Partially Implemented (Razorpay wired) |

### Shared User & Partner Features

| Feature Name | Purpose | Page Location | Status / Wiring |
| :--- | :--- | :--- | :--- |
| **Notification Center Drawer** | Side/full-screen panel showing inbox alerts filtered by category | Header Bell Button | Partially Implemented (Wired in Sprint 6) |
| **AI Assistant Chat overlay** | Interacts with AI support chatbot with venue context | Bottom Right Chat Bubble | Partially Implemented (Wired in Sprint 6) |

### Partner App Features

| Feature Name | Purpose | Page Location | Status / Wiring |
| :--- | :--- | :--- | :--- |
| **Today's Bookings Widget** | Lists bookings scheduled for today | Dashboard Home | Partially Implemented (Wired in Sprint 6) |
| **E-Ticket QR Scanner Screen** | Check-in tool using camera stream or manual code check | Header QR Scanner Button | Partially Implemented (Camera is placeholder) |
| **KYC File Uploader** | Uploads GST, PAN, or Bank statement to AWS S3 | Profile Tab | Partially Implemented (S3 Presign ready) |
| **Disputes Feed** | Displays open booking complaints and allows submitting responses | Payments Tab / Sidebar | Partially Implemented (Wired in Sprint 6) |
| **Review Reply Box** | Partner submits public responses to user reviews | Home / Reviews Panel | Partially Implemented (Wired in Sprint 6) |
| **8-Step Venue Setup Wizard** | Sequenced forms (basics, sport, price, hours, photos) to list turf | Venues Tab | Partially Implemented (Mock wizard) |
| **Slot Manager / Grid Builder** | Date-specific time checkboxes to create/block/unblock slots | Venue Detail Panel | Partially Implemented (Wired in Sprint 6) |
| **Dark Mode Switch** | Toggles dark/light color variables | Sidebar / Profile Footer | Fully Implemented |

### Admin Portal Features

| Feature Name | Purpose | Page Location | Status / Wiring |
| :--- | :--- | :--- | :--- |
| **KYC Document Viewer Modal** | Inspects partner docs (PDF/Img) with Verify/Reject actions | Partners Tab | Partially Implemented (Wired in Sprint 6) |
| **Milestone Configuration Form** | Configures milestone booking counts and coupon rewards | Users Tab (Milestones sub) | Partially Implemented (Wired in Sprint 6) |
| **Venue Approvals Controller** | Buttons to Approve, Reject (with reason), or Suspend venues | Venues Tab | Partially Implemented (Auto-notifies host) |
| **Slot Reassignment Tool**| Changes booking slots manually for players | Bookings Tab | Partially Implemented (Wired in Sprint 6) |
| **PAV Outstanding Ledger** | Lists outstanding cash amounts due from partners | Finance Tab | Partially Implemented (Wired in Sprint 6) |
| **Commission Rate Editor** | Adjusts platform fee % globally or per partner | Finance Tab | Partially Implemented (Deductions active) |
| **Surge Price / Demand Tags**| Adds Surge, High Demand, or Discount multipliers to slot groups | Slots/Demand Tab | Partially Implemented (Wired in Sprint 6) |
| **Broadcast Composer Form** | Prepares push notifications targeted by city, role, or sport | Notifications Tab | Partially Implemented (Wired in Sprint 6) |
| **Message Compliance Monitor**| Views and checks active user-partner chat logs | Messages Tab | Partially Implemented (UI mock) |

---

## 3. Screen Inventory

### User Screens
1. **Splash Screen (`/`)**
   - **User Type**: Athlete/Guest
   - **Purpose**: Displays app logo and boot animation, checks for active session tokens to auto-login.
   - **Connected Features**: Splash animation, auto-login redirect, TokenStore session fetch.
2. **Landing Website (`/landing`)**
   - **User Type**: Athlete/Guest
   - **Purpose**: Showcases platform benefits, featured venues, and offers CTA buttons to log in/sign up.
   - **Connected Features**: Featured carousel banner, featured venues slider, Login/Signup redirect CTAs.
3. **Login & Signup Screen (`/login`)**
   - **User Type**: Athlete/Guest
   - **Purpose**: Enforces multi-mode verification (phone OTP / email password) and profile creation.
   - **Connected Features**: OTP SMS request, verify OTP, social auth icons, forgot password wizard.
4. **Location Selection (`/location-prompt`)**
   - **User Type**: Authenticated User
   - **Purpose**: Requests GPS access or manual city inputs before booking.
   - **Connected Features**: Geolocation detector, manual city directory.
5. **Main Dashboard Portal (`/main`)**
   - **User Type**: Authenticated User
   - **Purpose**: Bottom navigation wrapper rendering the active application tab.
   - **Tabs Rendered**:
     - *Home Tab*: Lists venues, search input, sport filters, area filter, and sort options.
     - *My Bookings Tab*: Active/upcoming bookings list, cancel button, and refund tracking badge.
     - *Statistics Tab*: Play hours, bookings completed, tournaments joined.
     - *Milestones Tab*: Milestone badges displaying locked/unlocked statuses.
     - *Coupons Tab*: Coupon wallet showing active promo codes.
     - *Tournaments Tab*: Active tournaments list, search, and cancel notifications.
     - *Profile Tab*: Profile fields (DOB, Gender, Lang), edit profile button, and Sign Out.
6. **Venue Details & Slots (`/detail`)**
   - **User Type**: Authenticated User
   - **Purpose**: Detailed venue review, operational info, ratings, and slot picker calendar/grid.
   - **Connected Features**: Photo slider, amenities, reviews list, Date Picker, SlotButton status checker.
7. **Checkout & Payment (`/payment`)**
   - **User Type**: Authenticated User
   - **Purpose**: booking calculations, applying coupons, payment mode selection, and inputs.
   - **Connected Features**: Price breakdown, convenience fee calculator, Razorpay popup checkout, PAV toggle.
8. **Booking Confirmation Screen (`/confirmed`)**
   - **User Type**: Authenticated User
   - **Purpose**: Success checkmark confirmation, displays QR entry code and booking reference.
   - **Connected Features**: QR Code display, print/save options.

### Partner Screens
1. **Partner Login Screen (`/partner/login`)**
   - **User Type**: Venue Host/Partner
   - **Purpose**: Host authentication using phone OTP login.
   - **Connected Features**: OTP request, OTP comparison verification.
2. **Partner Dashboard Wrapper (`/partner/app`)**
   - **User Type**: Authenticated Partner
   - **Purpose**: Multi-tab layout for partner operations.
   - **Tabs Rendered**:
     - *Home Tab*: KPI cards, Today's Bookings widget, review reply section.
     - *Payments Tab*: Bank settings, settlements history table, refund notifications, Disputes inbox.
     - *Venues Tab*: Active venue list, "+ Add Venue" 8-step wizard, "+ Create Tournament" form, operational slot scheduling grid.
     - *Analytics Tab*: Revenue trend charts, hourly demand visualization, CSV export.
     - *Profile Tab*: Business profile editing, KYC document uploads, Dark mode toggle, and Sign Out.

### Admin Screens
1. **Admin Login Portal (`/admin/login`)**
   - **User Type**: Admin
   - **Purpose**: Email and password authentication console.
   - **Connected Features**: Password check, admin token save.
2. **Admin Operations Portal (`/admin/dashboard`)**
   - **User Type**: Authenticated Admin
   - **Purpose**: Central operations control board with sidebar navigation.
   - **Tabs Rendered**:
     - *Dashboard*: Core KPIs (revenue, users, bookings), Today's Bookings widget, trends charts.
     - *Users*: Registered users database, milestone triggers and rewards configurator.
     - *Partners*: Partner table, KYC Document Queue listing, KYCDocumentViewer modal.
     - *Venues*: Venue approvals interface, featured venue toggles, wishlist count details.
     - *Bookings*: Comprehensive booking ledger, slot reassignment buttons, booking cancellations.
     - *Finance*: Transaction ledger, PAV Tracking ledger, Commission Rate editor.
     - *Notifications*: Broadcast notification composer, delivery success rate dashboard logs.
     - *Reviews*: Moderation page to flag/approve user comments.
     - *Messages*: Audits partner-user chat transcripts.
     - *Demand*: Surge pricing modifier grid (surge, rainy day multipliers).

---

## 4. Role Permission Matrix

| Feature / Action | Athlete/User | Venue Partner | Platform Admin |
| :--- | :---: | :---: | :---: |
| Browse & Filter Venues | ✅ | ❌ | ❌ |
| Submit Venue Review | ✅ | ❌ | ❌ |
| Apply Coupon Discount | ✅ | ❌ | ❌ |
| Pay Deposit / PAV split | ✅ | ❌ | ❌ |
| Cancel Booking (Self) | ✅ | ❌ | ❌ |
| View Own Milestone Badges | ✅ | ❌ | ❌ |
| Register for Tournament | ✅ | ❌ | ❌ |
| AI Support Chat | ✅ | ✅ | ❌ |
| Access In-App Inbox | ✅ | ✅ | ❌ |
| Block / Unblock slots | ❌ | ✅ | ❌ |
| Add Venues (8-Step Wizard) | ❌ | ✅ | ❌ |
| Submit KYC Documents | ❌ | ✅ | ❌ |
| Reply to User Reviews | ❌ | ✅ | ❌ |
| Submit Dispute Statement | ❌ | ✅ | ❌ |
| Export Earnings CSV | ❌ | ✅ | ❌ |
| Launch Tournament | ❌ | ✅ | ✅ |
| Approve / Suspend Partners | ❌ | ❌ | ✅ |
| Verify KYC Documents | ❌ | ❌ | ✅ |
| Approve / Suspend Venues | ❌ | ❌ | ✅ |
| Toggle Featured Turf | ❌ | ❌ | ✅ |
| Reassign Booking Slots | ❌ | ❌ | ✅ |
| Refund Cancelled Bookings | ❌ | ❌ | ✅ |
| Apply Surge / Demand Tags | ❌ | ❌ | ✅ |
| Set Custom Commissions | ❌ | ❌ | ✅ |
| Broadcast push alerts | ❌ | ❌ | ✅ |
| Edit Milestone triggers | ❌ | ❌ | ✅ |
| Moderate Review Feed | ❌ | ❌ | ✅ |
| Monitor Chat Logs | ❌ | ❌ | ✅ |

---

## 5. User Journeys

### Athlete / User Journey
```
Launch App/Splash ──> Browse Landing Page ──> Register/Login Screen ──> Location Selector 
                                                                               │
                                                                               ▼
Booking Confirmed <── Razorpay Gateway <── Checkout & Payment <── Venue Detail & Slot Selection
       │
       ▼
Check-in at Turf ──> Play Session ──> Submit Rating & Review
```

1. **App Installation & Splash**: User launches the app, sees splash animation, and is redirected to the landing page.
2. **Registration / Login**: User clicks "Get Started", enters their mobile number, gets SMS OTP, and registers/logs in.
3. **Location Selection**: Selects a city (e.g. Delhi, Bangalore) to filter local turfs.
4. **Discovering Venues**: Filters by sport (e.g., Football), sorts by Price/Rating, and clicks a turf.
5. **Slot Selection**: Reviews photos and details, picks a date, selects available times (e.g., 6:00 PM - 7:00 PM), and clicks "Book Now."
6. **Booking & Promo Application**: Applies coupon code (e.g., 10% discount) and clicks "Online Payment."
7. **Razorpay Payments**: Completes payment on Razorpay modal with test card details.
8. **Confirmation & E-Ticket**: Receives entry ticket code (`APV-2026-XXXXXX`) and check-in QR code.
9. **Check-in & Play**: Arrives at turf, shows QR code, host scans user in.
10. **Review Submission**: Submits a review and star rating from booking history.
11. **Tournament Registration (Alternative)**: Navigates to tournaments, registers team, and pays registration fee.

### Venue Partner Journey
1. **Partner Registration**: Registers using OTP verification.
2. **KYC Documents Submission**: Enters business details and uploads GST certificate, PAN card, and Bank statement.
3. **KYC Verification**: Awaits admin review. Once verified, status changes to "Verified."
4. **Adding Venue Assets**: Launches the 8-step wizard to create the venue asset (basics, pricing, photos).
5. **Configuring Slot Timings**: Selects times (e.g. 6:00 AM to 10:00 PM) with base prices and builds slot grids.
6. **Slot Blocking**: Blocks out slots for maintenance or offline bookings, showing gray-striped blocks.
7. **Check-in Scanning**: Scans user QR code or inputs code manually to mark check-in.
8. **Review Replying**: Replies to user reviews.
9. **Earnings & Analytics**: Tracks payouts, dashboard charts, and exports earnings CSV.

### Platform Admin Journey
1. **Dashboard Review**: Audits platform revenue, booking metrics, and active users/partners.
2. **Partner Verification**: Views pending KYC queue, reviews S3 documents, and clicks "Verify" or "Reject."
3. **Venue Approvals**: Reviews unlisted venues, approves listings, or suspends active venues with reasons.
4. **Applying Dynamic Surge**: Selects slots on slots manager and applies surge tags (e.g. Surge +20%) to modify prices.
5. **Campaign Broadcasts**: Composes push broadcasts and targets by location/sport.
6. **Handling Cancellations & Disputes**: Resolves dispute claims (approving refunds, warning partners, or dismissing disputes).
7. **Review Moderation**: Approves or hides/moderates user reviews.

---

## 6. Business Model Reconstruction

The platform operates as a **two-sided sports venue booking marketplace**.

- **Customers**: Athletes/players (Demand) and sports venue owners (Supply).
- **Payment Structure**: Athletes pay booking slots and tournament registration fees. Partners pay platform commission on bookings.
- **Value Flow**:
  ```
  [ ATHLETES / DEMAND ]
        │  ▲
   Pays │  │ E-Tickets, QR codes,
   Fees │  │ Slot Bookings
        ▼  │
  [ APOV PLATFORM GATEWAY ]
        │  ▲
  Deducts  │ Lists Turf Slots,
     3% │  │ Schedules & KYC
        ▼  │
  [ VENUE HOSTS / PARTNERS ]
  ```
- **Booking Commissions (3% Platform fee)**: The platform retains a 3% commission on the total value of bookings.
- **Convenience Fees (4% Checkout fee)**: Added to online card/UPI bookings, charged to the user.
- **Pay-at-Venue Adjustments**: For PAV bookings, 30% is paid online as a deposit. The 3% fee on the *total booking* is tracked, and any unpaid commission is deducted from the partner's online payout during weekly settlements.
- **Featured Venue Subscriptions**: Premium search placement monetization.

---

## 7. Feature Completeness Matrix

| Feature Area | Complete (100%) | Partially Implemented | Status Details / Remaining Work |
| :--- | :---: | :---: | :--- |
| **Razorpay Webhook Verification** | ✅ | | Raw request body parsing, signature verification, payment validation |
| **Dark Mode Toggle** | ✅ | | Switch implemented across User, Partner, and Admin apps |
| **User Authentication** | | 85% | Registration, login, OTP verify ready. Remaining: end-to-end testing, production validation |
| **Partner Login & Onboarding** | | 85% | Screens and APIs ready. Remaining: integration testing |
| **Admin Login & Session** | | 85% | Auth screens, passwords, token store. Remaining: session validation |
| **Venue Setup Wizard** | | 85% | 8-step wizard complete. Remaining: final integration tests |
| **Venue Search & Filters** | | 85% | Search, sport/area filters ready. Remaining: live data tests |
| **Venue Detail Screen** | | 80% | Detail display, photo slider, reviews. Remaining: production content sync |
| **Multi-Turf Support** | | 65% | Assignment logic structure. Remaining: end-to-end operational tests |
| **Slot Management Console** | | 85% | Slot creation and slot schedules. Remaining: conflict tests |
| **Booking Checkout Flow** | | 80% | Calculations, coupons, creation workflow. Remaining: payment validation |
| **Booking Cancellation** | | 80% | Release slot, cancel workflow. Remaining: refund sync testing |
| **Slot Reassignment Console** | | 65% | Transfer controls and indicators. Remaining: complete validation |
| **Coupons Generator** | | 75% | Coupon creation, expiry, audience filter. Remaining: production validation |
| **Refund Ledger** | | 70% | Refund tracking and history logs. Remaining: automated verification |
| **PAV Outstanding Ledger** | | 70% | Balance tracking. Remaining: settlement reconciliation |
| **Settlements Ledger** | | 55% | Bank details forms, payout logs. Remaining: automated settlement run |
| **Partner Analytics Dashboard** | | 80% | KPI metrics, charts. Remaining: production data validation |
| **Admin Operations Dashboard** | | 80% | Dashboard KPIs, widgets. Remaining: performance optimization |
| **Milestones Configurator** | | 80% | Threshold and reward config. Remaining: reward trigger validation |
| **User Stats & Milestones** | | 70% | Stats cards, badges. Remaining: live data synchronization |
| **Tournament Portal** | | 75% | Listings, registrations, payments. Remaining: lifecycle testing |
| **FCM Broadcast Console** | | 75% | Notification composer, filters. Remaining: push verification |
| **Review Moderation Panel** | | 75% | Approval and flagging systems. Remaining: policy verification |
| **Dispute Response Panel** | | 70% | Management UI and status tracker. Remaining: dispute flow verification |
| **Real-Time Sockets** | | 60% | Live update framework. Remaining: stabilization and live testing |
| **E-Ticket QR Code** | | 75% | Layouts, QR generation. Remaining: live scan validation |
| **QR E-Ticket Scanner** | | 55% | Scanner interface, manual verify. Remaining: camera scanning integration |
| **Forgot Password Flow** | | 75% | OTP request, reset forms. Remaining: production testing |
| **S3 File Uploads** | | 10% | Presigned URL config. Remaining: full workflow and files UI |
| **Invoice PDF Generation** | | 30% | PDF service ready. Missing: print/download buttons, UI integration |
| **SMS & Email Integrations** | | 0% | Placeholders only. Missing: SMS/Email service provider hooks |
