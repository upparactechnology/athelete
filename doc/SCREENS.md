# Screen Inventory: Athlete's POV (APOV)

This document catalogs all screens and views across the Athlete App, Partner App, and Admin Portal.

---

## 1. Athlete / User Screens (Mobile-first)

### Splash Screen (`/`)
- **Purpose**: Displays the app logo and boots the initial animation.
- **Features**: Checks for active session tokens to auto-login.
- **Redirects**: Routes authenticated users to `/main` and guests to `/landing`.

### Landing Website (`/landing`)
- **Purpose**: Promotional landing page for guest visitors.
- **Features**: Showcases top-featured turfs via a sliding carousel and displays "Get Started" CTAs.
- **Redirects**: Routes users to `/login`.

### Login & Signup Screen (`/login`)
- **Purpose**: Access authentication panel.
- **Features**: OTP requests, OTP validation, and links to social OAuth identity logins.

### Location Selection (`/location-prompt`)
- **Purpose**: Sets regional filtering settings.
- **Features**: GPS geolocation request and city checklist options.

### Main Dashboard Portal (`/main`)
- **Purpose**: Tab navigation wrapper rendering the active application tab.
- **Tabs Rendered**:
  - **Home Tab**: Renders the featured carousel banner, search field, sport filters, location selector, and turf listings.
  - **My Bookings Tab**: Renders active and past booking cards, cancellation triggers, and refund badges.
  - **Statistics Tab**: Renders play counters, tournament metrics, and unlocked milestone badges.
  - **Coupons Tab**: Renders the user's coupon wallet.
  - **Tournaments Tab**: Renders registered and open local tournaments.
  - **Profile Tab**: Renders user info, editing triggers, theme selections, and Sign Out buttons.

### Venue Details & Slots (`/detail`)
- **Purpose**: Renders detailed venue information and reviews.
- **Features**: Renders a date picker calendar, review lists, photo sliders, and the slot grids.

### Checkout & Payment (`/payment`)
- **Purpose**: Renders fee calculation summaries.
- **Features**: Renders cost breakdowns, convenience fees, coupon application, and payment options.

### Booking Confirmation Screen (`/confirmed`)
- **Purpose**: Displays booking confirmation.
- **Features**: Renders payment verification messages and check-in QR ticket details.

---

## 2. Venue Partner Screens (Mobile-first)

### Partner Login Screen (`/partner/login`)
- **Purpose**: Partner phone authentication.
- **Features**: OTP request and comparison logic.

### Partner Dashboard Wrapper (`/partner/app`)
- **Purpose**: Tab navigation wrapper rendering host operations tabs.
- **Tabs Rendered**:
  - **Home Tab**: Renders KPI stats (total earnings, active listings, active slots), Today's Bookings list, review reply triggers, and QR Scanner buttons.
  - **Payments Tab**: Renders bank routing setup forms, settlement history, and Dispute feeds.
  - **Venues Tab**: Renders listed turf assets, "+ Add Venue" setup wizard, and slot grid builders.
  - **Analytics Tab**: Renders revenue trend charts and hourly slot demand indicators.
  - **Profile Tab**: Renders business profiles, S3 KYC file upload fields, and dark theme toggles.

---

## 3. Platform Admin Screens (Desktop-only)

### Admin Login Portal (`/admin/login`)
- **Purpose**: Admin email/password login screen.
- **Features**: Hardcoded bcrypt comparison validation checks.

### Admin Operations Portal (`/admin/dashboard`)
- **Purpose**: Administrative panel with sidebar navigation.
- **Tabs Rendered**:
  - **Dashboard**: Renders platform KPI logs (users, bookings, earnings), Today's Bookings widgets, and analytics charts.
  - **Users Tab**: Renders search tables, user profile tools, and milestone configurations.
  - **Partners Tab**: Renders partner tables, verification detail windows, and KYC Document Viewer modals.
  - **Venues Tab**: Renders listed assets tables, venue detail review panels, and Pin/Unpin buttons.
  - **Bookings Tab**: Renders booking records, search filters, slot reassignment tools, and refund controls.
  - **Finance Tab**: Renders payment ledgers, Pay-at-Venue outstanding balances, and global commission rate editors.
  - **Notifications Tab**: Renders FCM broadcast composers and logs.
  - **Reviews Tab**: Renders moderation queues allowing admins to flag/hide user reviews.
  - **Messages Tab**: Renders active user-partner chat logs.
  - **Demand Tab**: Renders slot grids allowing admins to apply surge tags.
