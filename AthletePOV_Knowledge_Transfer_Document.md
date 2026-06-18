# Athlete's POV (APOV) Full-Stack Knowledge Transfer Document
*A Complete A–Z Developer Reference for the AthletePOV Sports Venue Booking Platform*

- **Version**: 1.0 (Sprint 1–6 Complete)
- **Date**: April 2026
- **Apps**: User App, Partner App, Admin Portal
- **Stack**: Express + TypeScript, PostgreSQL + Prisma, Redis, Razorpay, Firebase FCM, Flutter

---

## 1. Project Overview

### What is AthletePOV?
AthletePOV (APOV) is a multi-sided sports venue booking platform (akin to Hudle and KheloMore in India). It connects three distinct stakeholders on a single unified backend:
1. **Athletes (End Users)**: Everyday athletes who want to discover and book sports facilities.
2. **Partners (Venue Owners)**: Facility owners who list and manage their playing grounds, schedules, and earnings.
3. **Administrators (Platform Admins)**: Platform operators who govern the entire ecosystem (approvals, disputes, KYC, coupons, banners, etc.).

All interactions flow through a unified Express/TypeScript REST API to a shared PostgreSQL database.

### The Three Applications

| Application | Users | Primary Purpose | Key Capabilities |
| :--- | :--- | :--- | :--- |
| **User App** | Athletes / Players | Discover and book sports venues | Browse venues, select slots, pay online or at venue, view e-tickets, tournaments, coupons, wishlist |
| **Partner App** | Venue Owners | Manage venue listings and earnings | Create venues, configure slots, view bookings, scan e-tickets (QR), manage disputes, track analytics |
| **Admin Portal** | Platform Admins | Govern the entire platform | Approve venues/KYC, manage users & partners, set coupons, send broadcasts, view finance, manage content |

### Business Model & Platform Constants
The platform monetizes through commissions and convenience fees. These constants are hardcoded in `bookings.service.ts` and must never be changed inline:

- `CONVENIENCE_FEE_RATE`: **4%** (Added to every online booking, charged to the user)
- `COMMISSION_RATE`: **3%** (Platform commission taken from the total booking amount)
- `GST_RATE`: **18%** (GST applied on top of the 3% platform commission)
- `PAV_ONLINE_PCT`: **30%** (Collected online to secure the slot for Pay-at-Venue bookings)
- `PAV_VENUE_PCT`: **70%** (Collected at the physical venue for Pay-at-Venue bookings)

### Technology Stack

| Layer | Technology | Version / Details |
| :--- | :--- | :--- |
| **Runtime** | Node.js | v20+ |
| **Language** | TypeScript | Strict mode |
| **Web Framework** | Express.js | v4 + Helmet, CORS, Morgan, Compression |
| **ORM** | Prisma | PostgreSQL provider |
| **Database** | PostgreSQL | v16 — UUID primary keys via `uuid_generate_v4()` |
| **Cache / Queue** | Redis | v7 — OTP storage, slot locks, availability cache |
| **Payments** | Razorpay | Orders API, webhook HMAC verification |
| **Push Notifications**| Firebase Admin SDK (FCM) | Multi-token dispatch |
| **File Storage** | AWS S3 (or local mock) | Presigned URLs for KYC documents |
| **Input Validation** | Zod | Environment schema + request bodies |
| **Rate Limiting** | express-rate-limit | Global, auth, OTP, payment tiers |
| **Logging** | Winston | Structured JSON + HTTP request log |
| **Frontend** | Flutter (Dart SDK) | Native compiled Android & iOS apps, web support |
| **Dev Tools** | VS Code / Android Studio | Windows PowerShell + Flutter CLI |

---

## 2. System Architecture

### High-Level Architecture
All three frontend apps are built using Flutter (Dart) and communicate exclusively with the backend REST API (port 4000). The backend follows a modular architecture where each domain (auth, venues, bookings, etc.) is isolated into its own service/controller/routes trilogy. External services (Razorpay, Firebase, S3) are initialized once in `src/config/` and injected via singleton getters.

```
User App (Flutter)       ----> Bearer JWT ---------------------> Backend (Port 4000)
Partner App (Flutter)    ----> Bearer JWT ---------------------> Express + TypeScript
Admin Portal (Flutter)   ----> Bearer JWT + X-Admin-Role ------> [/api prefix]
                                                                  |--> Prisma ORM (PostgreSQL v16)
                                                                  |--> Redis v7 (Slot Locks, OTP, Cache)
                                                                  |--> Razorpay, Firebase FCM, AWS S3
```

### Request Flow
Every API request travels through the following middleware chain:
1. **Client sends HTTP request**: Bearer token in `Authorization` header; `X-Admin-Role` for admin routes.
2. **Helmet**: Adds security headers (XSS, HSTS, etc.).
3. **CORS middleware**: Validates origin against `ALLOWED_ORIGINS` env var.
4. **Raw body parser** (webhook only): `express.raw()` preserves Buffer for Razorpay HMAC verification.
5. **express.json()**: Parses JSON body for all other routes (2 MB limit).
6. **Request ID injection**: Generates `X-Request-ID` UUID for tracing.
7. **Morgan HTTP logger**: Logs method, path, status, and response time to Winston stream.
8. **Global rate limiter**: 100 req / 15 min per IP (configurable).
9. **Route match**: Express matches to the correct module router.
10. **authenticate middleware**: Verifies JWT, rejects expired/invalid tokens, and blocks suspended accounts.
11. **authorize middleware**: Checks role against allowed roles array.
12. **Controller**: Parses request parameters and calls the service function.
13. **Service**: Business logic, Prisma queries, and Redis operations.
14. **Error handler**: Catches `AppError` subclasses and formats the JSON error response.

---

## 3. Folder & File Structure

### Backend Structure (`src/`)
```
src/
├── app.ts                          # Express app bootstrap, all middleware, route mounting
├── index.ts                        # Entry point — starts server
├── config/
│   ├── env.ts                      # Zod-validated environment variables (crashes on missing vars)
│   ├── prisma.ts                   # Prisma client singleton → import { prisma }
│   ├── redis.ts                    # Redis client singleton + RedisKeys helpers
│   ├── razorpay.ts                 # Razorpay SDK singleton + rupeesToPaise helper
│   ├── firebase.ts                 # Firebase Admin SDK + sendPushToToken / sendPushToMultipleTokens
│   ├── logger.ts                   # Winston logger (stdout + file) + httpLogStream for Morgan
│   └── cors.ts                     # CORS options from ALLOWED_ORIGINS env var
├── middleware/
│   ├── authenticate.ts             # JWT Bearer verification → req.user = {id, role, status}
│   ├── authorize.ts                # RBAC guard: authorize('user'|'partner'|'admin')
│   ├── errorHandler.ts             # Global error → JSON { error: { code, message } }
│   ├── rateLimiter.ts              # globalRateLimiter, authLimiter, otpLimiter, paymentLimiter
│   ├── requestId.ts                # Injects X-Request-ID UUID header
│   └── notFoundHandler.ts          # 404 catch-all → AppError
├── shared/
│   ├── types/
│   │   └── index.ts                # UserRole, AuthRequest, JwtAccessPayload, PaginatedQuery
│   └── utils/
│       ├── errors.ts               # AppError hierarchy (NotFound, Validation, Forbidden, etc.)
│       └── response.ts             # sendSuccess(), sendPaginated() response helpers
└── modules/                        # 13 domain modules — each has service + controller + routes
    ├── auth/                       # OTP request/verify, JWT refresh, logout, Google/Apple OAuth
    ├── users/                      # Profile CRUD, bookings history, wishlist toggle
    ├── partners/                   # Partner onboarding, KYC submission, profile
    ├── venues/                     # Venue CRUD, discovery, reviews, admin approval
    ├── slots/                      # Slot definitions, availability, Redis locking, demand tags
    ├── bookings/                   # Booking lifecycle, e-tickets, cancellation, disputes
    ├── payments/                   # Razorpay orders, webhook, refunds, settlements
    ├── notifications/              # FCM dispatch, in-app inbox, admin broadcast
    ├── coupons/                    # Coupon wallet, validation, admin CRUD
    ├── analytics/                  # KPIs for user/partner/admin
    ├── tournaments/                # Tournament listing, registration, status machine
    ├── content/                    # Banners/promotions for each app
    └── documents/                  # KYC document upload (S3 presign), admin review
```

### Frontend Structure (`lib/`)
```
lib/
├── api_client.dart                 # Shared Dio API client with interceptors
├── main.dart                       # Entry point, initializes routing and dependencies
├── models/                         # Shared Dart serialization models
├── athlete_app/                    # User App views and logic (Riverpod state)
├── partner_app/                    # Partner App views and logic
└── admin_portal/                   # Admin Portal views and logic
```

> [!IMPORTANT]
> **Critical Flutter/Dart Rules**:
> - **State Management**: Use `flutter_riverpod` or `bloc` for state management to separate UI from business logic. Avoid calling backend APIs inside widget build methods.
> - **Secure Token Storage**: Tokens must be stored in secure device storage using `flutter_secure_storage` instead of unsecured local storage.

### Key File Roles
- `env.ts`: Zod schema configuration validation. The server crashes immediately at startup if any required variable is missing. *Never use non-ASCII characters here.*
- `authenticate.ts`: Verifies JWT and sets `req.user = {id, role, status}`. Rejects blocked/suspended accounts. Supports `optionalAuthenticate` for public+personalized routes.
- `authorize.ts`: Role-Based Access Control (RBAC) middleware supporting `authorize('partner')`, `userOnly`, `partnerOnly`, `adminOnly`, `requireAdminHeader`, and `selfOrAdmin`.
- `bookings_service.ts`: Core booking logic containing calculations and lifecycle triggers (`calculatePricing()`, `initiateBooking()`, `confirmBooking()`, `cancelBooking()`).
- `api_client.dart`: Handles Dio client setup, JWT header injection, secure token rotation on `401 Unauthorized` responses via Dio interceptors.
- `schema.prisma`: Defines all 26+ database tables. Uses UUID primary keys and `Prisma.Decimal` for monetary values.

---

## 4. Authentication System

### OTP-Based Login Flow
APOV uses phone-based OTP authentication as the primary login method. Regular users and partners do not have passwords. Admins use a separate flow with hardcoded credentials stored as bcrypt hashes in environment variables.

1. **Request OTP (`POST /api/auth/request-otp`)**:
   - Rate-limited to 3 requests per phone per 10 minutes via Redis.
   - Generates a 6-digit OTP, bcrypt-hashes it, and stores the `{hash, role}` in Redis with a 5-minute TTL.
   - Simulates SMS send.
2. **Verify OTP (`POST /api/auth/verify-otp`)**:
   - Brute-force guard allows a maximum of 5 attempts before auto-deleting the OTP from Redis.
   - Uses `bcrypt.compare()` to check the OTP.
   - Upserts the `User` or `Partner` in the DB.
   - Issues an `accessToken` (15m expiry) and a `refreshToken` (7d expiry, stored in the `refresh_tokens` DB table).
   - Returns `{ accessToken, refreshToken, isNewAccount, role }`.
3. **Refresh Token (`POST /api/auth/refresh`)**:
   - Verifies the JWT signature and validates `token_id` in the `refresh_tokens` table.
   - Rotates tokens: revokes the old token and issues a new `accessToken` + `refreshToken` pair.
4. **Logout (`POST /api/auth/logout`)**:
   - Revokes the refresh token in the DB by setting `revoked_at` and instructs the client to clear `localStorage`.
5. **Google OAuth (`POST /api/auth/google`)**:
   - Verifies Google ID token and upserts user and `oauth_identities` records.
6. **Apple OAuth (`POST /api/auth/apple`)**:
   - Blocked in production (returns `501 Not Implemented`). Development-only.

### JWT Token Structure
- **Access Token Payload** (signed with `JWT_ACCESS_SECRET`, expires in 15 minutes):
  ```json
  {
    "sub": "user-uuid-here",
    "role": "user | partner | admin",
    "status": "active | blocked | suspended"
  }
  ```
- **Refresh Token Payload** (signed with `JWT_REFRESH_SECRET`, expires in 7 days):
  ```json
  {
    "sub": "user-uuid-here",
    "role": "user | partner | admin",
    "jti": "refresh_token_uuid_in_db"
  }
  ```

*Usage*: Protected endpoints require the `Authorization: Bearer <access_token>` header. Admin endpoints additionally require the `X-Admin-Role: admin` header.

### Security Safeguards
- OTP is bcrypt-hashed before being stored in Redis; plain OTPs are never persisted.
- OTP is deleted from Redis immediately after a successful verification.
- Refresh tokens are rotated on every use; the old token is immediately revoked.
- Accounts are checked on every request; blocked/suspended users are rejected at the JWT middleware layer.
- **UTF-8 Limitation Warning**: NEVER use non-ASCII characters (em-dashes `—`, smart quotes, emoji) in `env.ts` or any backend TypeScript files. The ESM loader will crash silently with an `[Object: null prototype]` error.

---

## 5. Venue & Slot Management

### Venue Lifecycle
- **`unlisted`**: Venue is newly created by a Partner and is awaiting platform admin review. It is not visible to users.
- **`listed`**: Approved by admin and discoverable in searches.
- **`suspended`**: Temporarily hidden from search by an admin.

Partners can only list venues after their KYC status is marked `verified`. Featured venues are tracked in a Redis sorted set (`featured_venues`) instead of the DB, enabling high-performance reads and score-based ordering.

### Slot Locking — Concurrency Guard
To prevent double-booking, the booking service uses a Redis-based slot lock before initiating payment:
1. **Acquire Lock**: Calls `Redis SET slot:lock:X 'sessionA' NX EX 15`. If it returns `'OK'`, the user proceeds to payment.
2. **Lock Contention**: If another user attempts to book the same slot, the `SET NX` command returns `null` and the API responds with a `409 Slot Locked` error.
3. **Release**: The lock is deleted when payment is confirmed or automatically expires after 15 seconds.

### Slot Statuses
- **`available`**: Default state on creation; open for bookings.
- **`booked`**: Reserved after payment confirmation.
- **`blocked_by_partner`**: Blocked by host via `PATCH /:venueId/slots/:id/block` (e.g. for maintenance).
- **`blocked_by_admin`**: Blocked via admin action.

### Demand Tags (Dynamic Surge Pricing)
Admins can apply demand tags (such as `peak_hours`, `high_demand`, `last_few_slots`, `flash_sale`, `premium_slot`, `weekend_special`) to slots. When active, the slot price increases by **50%**. Removing the tag reverts the slot to the venue's base price.

### Redis Caching Strategy

| Redis Key Pattern | TTL | Caches | Invalidated When |
| :--- | :--- | :--- | :--- |
| `slot:lock:{slotId}` | 15s | Slot booking lock (NX) | Payment is confirmed or lock expires |
| `slots:avail:{venueId}:{date}` | 60s | Availability list of slots | Any slot write for that venue and date |
| `featured_venues` | No TTL | Sorted set of featured venue IDs | Admin pins or unpins a venue |
| `otp:{phone}` | 5 min | bcrypt OTP hash + role | OTP is verified or expires |
| `otp:attempts:{phone}` | 5 min | Failed verification attempts | Reset on successful verify |

---

## 6. Booking System

### Booking Lifecycle (Two-Step Flow)
Bookings are split into two phases to support asynchronous Razorpay payment confirmations:
1. **Initiate Booking (`POST /api/bookings`)**:
   - Validates slot availability and acquires the Redis slot lock (15s).
   - Calculates fee breakdown and applies coupons.
   - Checks the idempotency key `booking:idem:{userId}:{slotId}` to prevent rapid double-clicks.
   - Creates the booking in the DB with `PENDING` status.
2. **Client-Side Payment**:
   - The frontend launches the Razorpay SDK hosted checkout UI.
   - On success, it receives a payment signature, order ID, and transaction ID.
3. **Confirmation Webhook / Client Verify**:
   - Webhook checks Razorpay's HMAC signature.
   - Updates booking status to `CONFIRMED` in the DB and marks the slot as `booked`.
   - Dispatches Firebase FCM push notifications to the user and partner.
4. **Cancellation (`PATCH /api/bookings/:id/cancel`)**:
   - Resets slot status to `available` and invalidates Redis availability caches.
   - Initiates a refund if cancelled within 24 hours. DB status becomes `CANCELLED`.

### Fee Calculation Logic
```javascript
// CARD or UPI payment
discounted = base_amount - coupon_discount;
convenience = discounted * 0.04; // 4% convenience fee
total_amount = discounted + convenience;
online_amount = total_amount;
venue_amount = 0;

// PAY AT VENUE (PAV)
discounted = base_amount - coupon_discount;
online_amount = discounted * 0.30; // 30% online deposit to lock slot
venue_amount = discounted * 0.70;  // 70% cash collected at venue
total_amount = discounted;
convenience = 0; // Convenience fee is waived for PAV

// FREE SLOT
All amounts = 0; booking is immediately marked CONFIRMED.

// Platform Split (Internal bookkeeping)
commission = total_amount * 0.03; // 3% platform commission
gst = commission * 0.18;          // 18% GST on platform commission
partner_amount = total_amount - commission - gst;
```

### E-Ticket System
Every successful booking generates a unique ticket code with the format `APV-2026-XXXXXX` (where `XXXXXX` represents 6 random hex characters). This code is indexed in `bookings.eticket_code` and is scanned via the Partner App QR scanner to check in players.

---

## 7. Payment System

### Razorpay Integration Flow
1. **User App** requests payment initiation via `POST /api/payments/initiate`. Backend creates the Razorpay order and returns `order_id` and platform configuration.
2. **Razorpay SDK** opens a payment modal. The user submits card/UPI details.
3. **Razorpay** returns `{ razorpay_order_id, razorpay_payment_id, razorpay_signature }` to the client.
4. **User App** submits credentials to `POST /api/payments/verify`. Backend verifies the signature and confirms the booking.
5. **Razorpay Webhook** (`POST /api/payments/webhook`) acts as a fallback for asynchronous validation and handles refund/dispute updates.

> [!IMPORTANT]
> **Webhook Security Critical Rule**: Razorpay computes its signature over the RAW request body bytes.
> In `app.ts`, the raw parser MUST be placed before the JSON parser:
> ```javascript
> app.use('/api/payments/webhook', express.raw({ type: 'application/json' })); // 1. FIRST
> app.use(express.json({ limit: '2mb' }));                                    // 2. SECOND
> ```
> Signature verification in `payments.service.ts` uses:
> ```javascript
> const expectedSig = crypto.createHmac('sha256', env.RAZORPAY_WEBHOOK_SECRET)
>   .update(rawBody)
>   .digest('hex');
> if (expectedSig !== receivedSig) throw new ForbiddenError('Invalid signature');
> ```
> *Note*: The webhook endpoint must ALWAYS return HTTP `200` to prevent Razorpay from retrying, even if processing fails internally.

---

## 8. Settlement & Commission System

### Weekly Settlement Cycle
Razorpay settles platform funds to APOV's bank account weekly. The platform then runs a billing process to calculate partner earnings and disburse bank transfers.
```
platform_fee = gross_amount * 0.03 * (1 + 0.18) // 3% commission + 18% GST
net_amount = gross_amount - platform_fee
```
Settlement records are stored in the `settlements` table. Payout statuses follow: `calculating` -> `pending` -> `on_hold` (if a dispute is active) -> `settled` | `failed`.

---

## 9. Notification System

### Architecture
The Notification Service is a leaf node; it does not import other core services. When called via `sendNotification()`, it:
1. Writes the alert to the `user_notifications` table (in-app inbox).
2. Attempts to push a Firebase FCM alert using tokens retrieved from `users.fcm_token` or `partners.fcm_token`.
3. If FCM fails, the notification is still accessible via the in-app inbox.

### Target Audiences for Broadcasts
Admins can trigger push broadcasts to targeted cohorts:
- `all_users`, `all_partners`, `specific_user`, `specific_partner`, `area` (geofenced), `sport` (sports preferences), `all` (everyone).

---

## 10. Coupon & Milestone System

### Coupon Validation Order
Validation checks run in the following sequence; the first failure throws an error:
1. Coupon exists and `is_active = true`.
2. Current date falls within `valid_from` and `valid_until`.
3. Global coupon usage limit has not been reached.
4. Total order value meets the `min_order_value` threshold.
5. User has not exceeded their `per_user_limit` (evaluated via DB counts).

### Milestone System
Gamified milestone coupons are automatically issued on booking achievements:
- `first_step`: User completes their **1st** booking.
- `hat_trick`: User completes their **3rd** booking.
- `weekly_warrior`: User completes **3 bookings in 7 days**.
- `court_regular`: User completes **10 total bookings**.

---

## 11. Tournament System

### Tournament Lifecycle
```
upcoming (Registration Open) ──> open (Active) ──> full (Limit Reached) ──> completed
                                   │
                                   └──> cancelled (Triggers automated refunds)
```
Users register via `POST /api/tournaments/:id/register` and pay the entry fee via Razorpay. Cancelling a tournament automatically processes refunds for all registrants.

---

## 12. Document Verification & KYC

### Onboarding Flow
1. **Partner** requests an S3 upload link: `POST /api/documents/presign`.
2. **Partner** uploads the file directly to S3 (no server bandwidth consumed).
3. **Partner** notifies the backend, creating a pending `PartnerDocument` record.
4. **Admin** inspects the document via the `KYC Document Viewer Modal` and approves/rejects the file.
5. Once all documents (e.g. GST certificate, PAN card, ownership proof) are verified, the partner's status updates to `verified`, allowing them to create venues.

---

## 13. Database Schema Highlights

The database contains **26+ tables** with key architecture parameters:
- **UUIDs** are used for all primary keys to guarantee uniqueness.
- **Timestamptz** timezone-aware fields are configured globally (essential for IST handling).
- **Prisma.Decimal** is used for all pricing fields to prevent floating-point calculation errors.
- **Wishlist** enforces a unique composite constraint on `(user_id, venue_id)`.
- **Sport Types** are stored as a string array (`String[]`) directly on the venue model to simplify query complexity.

---

## 14. Key Development Rules & Extensions

### How to Add a New Backend Module
1. Create a module directory: `src/modules/new_feature/`.
2. Build the three core layers:
   - `new_feature.service.ts`: Business logic and Prisma queries.
   - `new_feature.controller.ts`: HTTP request parsing and response handling.
   - `new_feature.routes.ts`: Router configuration containing JWT auth middleware.
3. Register the router in `app.ts` using `app.use('/api/new_feature', newFeatureRoutes)`.
4. Run validation check: `npx tsc --noEmit`.

### How to Add a New Frontend Feature
- **Decouple Views and ViewModels**: Add new features in separate Flutter widget classes inside feature directories rather than nesting code.
- **Utilize Code Generation**: When modifying state models or API entities, run `flutter pub run build_runner build --delete-conflicting-outputs` to regenerate json serializers and providers.
- **Update api_client.dart**: Register any new endpoints or service objects in the Dio service registration map; never execute direct raw HTTP/dio calls in views.

---

## 15. Known Issues & Critical Pitfalls

- **Non-ASCII in TS Files**: Characters like em-dashes `—` or emojis will corrupt the UTF-8 compilation and cause silent ESM crashes. Scan code with ripgrep (`[^ -~]`) to identify invalid characters.
- **Improper Riverpod/BLoC state updates**: Triggering state updates or API calls inside widget build functions causes continuous re-build loop cycles. Use `ref.read` in callbacks or lifecycle hooks.
- **Webhook Raw Parser**: Reversing the order of `express.raw()` and `express.json()` in `app.ts` breaks Razorpay webhook authentication.
- **EADDRINUSE**: If ports are locked, terminate running node instances:
  - Windows: `taskkill /F /IM node.exe`
  - Linux/Mac: `kill -9 $(lsof -ti:4000)`
- **Redis Name**: The Docker container name is `athletes-redis` (not `redis`).
- **Prisma Decimals**: Decimal money values must be explicitly cast using `Number(val)` before performing mathematical calculations in TypeScript.
- **Time Formatter**: Frontend time formatter `f24()` will crash if passed a raw database Time object. Convert time objects to strings before formatting.
