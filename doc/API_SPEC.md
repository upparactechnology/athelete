# API Specification: Athlete's POV (APOV)

All client-to-server communications utilize standard REST conventions.

- **Base URL**: `http://localhost:4000/api`
- **Port**: 4000

---

## Response Envelopes

### Success Envelope
All successful requests return a JSON response matching the following envelope:
```json
{
  "success": true,
  "data": {}
}
```

### Error Envelope
Failed API transactions return standard HTTP error codes accompanied by structured error logs:
```json
{
  "success": false,
  "error": {
    "code": "SLOT_LOCKED | AUTH_FAILED | VALIDATION_ERROR | NOT_FOUND",
    "message": "Human-readable description of error.",
    "details": {}
  }
}
```

---

## Endpoints

### 1. Authentication Service (`/auth`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/auth/request-otp` | Public | Generates a 6-digit verification code, stores its bcrypt hash in Redis, and simulates sending an SMS. Rate-limited to 3 requests per 10 minutes. |
| `POST` | `/auth/verify-otp` | Public | Verifies the OTP. Upserts the `User` or `Partner` records and issues an `accessToken` (15m TTL) and a `refreshToken` (7d TTL). |
| `POST` | `/auth/refresh` | Public | Rotates the JWT: revokes the old refresh token and issues a new token pair. |
| `POST` | `/auth/logout` | User/Partner | Revokes the active refresh token and instructs the client to clear local storage tokens. |
| `POST` | `/auth/google` | Public | Verifies Google ID token assertions and handles registration/login flows. |
| `POST` | `/auth/apple` | Public | Blocked in production (returns `501 Not Implemented`). |

---

### 2. User Profiles (`/users`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/users/me` | User | Retrieves profile information for the authenticated user. |
| `PATCH` | `/users/me` | User | Updates profile properties (e.g. DOB, gender, language preferences). |
| `GET` | `/users/me/bookings` | User | Retrieves paginated booking history. |
| `GET` | `/users/me/wishlist` | User | Retrieves the user's wishlisted venues. |
| `POST` | `/users/me/wishlist/:venueId` | User | Toggles the wishlist status of a venue. |

---

### 3. Partner Operations (`/partners`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/partners/register` | Partner | Completes partner onboarding information. |
| `POST` | `/partners/submit-kyc` | Partner | Submits S3 file links for partner compliance verification. |
| `GET` | `/partners/me` | Partner | Retrieves the partner's profile and venue summary details. |
| `PATCH` | `/partners/me` | Partner | Updates partner information. |

---

### 4. Venue Catalog (`/venues`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/venues` | Public | Lists venues. Supports city, sport types, and price filtering. |
| `POST` | `/venues` | Partner | Creates a new venue. Requires partner KYC status to be `verified`. |
| `GET` | `/venues/featured` | Public | Retrieves featured venues. High-performance cache query (Redis sorted set). |
| `GET` | `/venues/mine` | Partner | Retrieves the partner's listed venues. |
| `GET` | `/venues/admin/all` | Admin | Lists all venues, including unlisted and suspended entries. |
| `GET` | `/venues/:id` | Public | Retrieves detailed venue information, photos, reviews, and wishlist status. |
| `PATCH` | `/venues/:id` | Partner/Admin | Updates venue details. |
| `GET` | `/venues/:id/reviews` | Public | Retrieves paginated reviews. |
| `POST` | `/venues/:id/reviews` | User | Submits a review. Requires a completed booking at the venue. |
| `PATCH` | `/venues/admin/:id/status` | Admin | Approves, rejects, or suspends a venue. |
| `PATCH` | `/venues/admin/:id/feature` | Admin | Pins or unpins a venue from the featured sorted set. |

---

### 5. Slot Scheduling (`/venues/:venueId/slots`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/venues/:venueId/slots` | Public | Retrieves time slots and availability status for a date. |
| `GET` | `/venues/:venueId/slots/dates` | Public | Retrieves dates with available slots within a calendar range. |
| `POST` | `/venues/:venueId/slots` | Partner | Bulk creates slots for scheduling templates. |
| `PATCH` | `/venues/:venueId/slots/:id/price` | Partner | Updates slot base pricing. |
| `POST` | `/venues/:venueId/slots/:id/block` | Partner | Manually blocks a slot, changing its status to `blocked_by_partner`. |
| `DELETE` | `/venues/:venueId/slots/:id/block` | Partner | Unblocks a previously blocked slot. |
| `DELETE` | `/venues/:venueId/slots/:id` | Partner | Deletes a slot. |
| `POST` | `/slots/admin/demand-tag` | Admin | Applies surge tags (e.g. `peak_hours`) that increase slot prices by 50%. |
| `DELETE` | `/slots/admin/demand-tag` | Admin | Removes applied surge tags, restoring the slot's base price. |

---

### 6. Bookings & Tickets (`/bookings`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/bookings/preview` | Public | Preview calculated fees, convenience fees, and taxes before checkout. |
| `POST` | `/bookings` | User | Initiates booking. Acquires a 15-second Redis slot lock. |
| `GET` | `/bookings` | User | Lists the user's booking history. |
| `GET` | `/bookings/:id` | User/Partner/Admin | Retrieves details for a booking. |
| `PATCH` | `/bookings/:id/cancel` | User/Admin | Cancels a booking. Releases the slot and initiates a refund if eligibility conditions are met. |
| `GET` | `/bookings/:id/ticket` | User/Partner | Retrieves an e-ticket with a QR code. |
| `POST` | `/bookings/:id/checkin` | Partner | Checks in a player by validating their E-ticket QR code. |
| `POST` | `/bookings/:id/dispute` | User | Raises a payment or booking dispute. |
| `GET` | `/bookings/admin/all` | Admin | Lists all booking records across the platform. |
| `PATCH` | `/disputes/:id/resolve` | Admin | Resolves a dispute and processes refunds if applicable. |

---

### 7. Payments & Billing (`/payments`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/payments/initiate` | User | Creates a Razorpay order record for a pending booking. |
| `POST` | `/payments/verify` | User | Validates client-side Razorpay hashes and marks bookings `CONFIRMED`. |
| `POST` | `/payments/webhook` | Webhook (HMAC) | Receives events from Razorpay. *order_id* matches are verified. |
| `POST` | `/payments/refund` | Admin | Initiates a manual booking refund. |
| `GET` | `/payments/booking/:id` | User/Admin | Retrieves transaction details for a booking. |
| `GET` | `/payments/settlements` | Partner | Retrieves settlement history. |
| `GET` | `/payments/admin/transactions` | Admin | Retrieves the full platform financial ledger. |

---

### 8. Notifications & Marketing (`/notifications`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/notifications` | User/Partner | Retrieves notifications from the in-app inbox. |
| `PATCH` | `/notifications/:id/read` | User/Partner | Marks a notification as read. |
| `PATCH` | `/notifications/read-all` | User/Partner | Marks all notifications as read. |
| `POST` | `/notifications/admin/broadcast` | Admin | Dispatches an FCM push broadcast to a targeted cohort. |
| `GET` | `/notifications/admin/broadcasts` | Admin | Retrieves history logs of sent broadcasts. |

---

### 9. Coupons (`/coupons`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/coupons` | User | Lists valid coupons in the user's wallet. |
| `GET` | `/coupons/validate` | User | Validates a coupon code and returns the discount amount. |
| `GET` | `/coupons/:code` | User | Retrieves coupon configuration details. |
| `GET` | `/coupons/admin` | Admin | Lists all coupons. |
| `POST` | `/coupons/admin` | Admin | Creates a coupon. |
| `PATCH` | `/coupons/admin/:id` | Admin | Updates coupon properties. |
| `DELETE` | `/coupons/admin/:id` | Admin | Deletes a coupon. |

---

### 10. Analytics (`/analytics`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/analytics/user/me` | User | Retrieves user statistics and milestone progress. |
| `GET` | `/analytics/partner/:id/dashboard` | Partner | Retrieves partner KPIs (revenue, booking trends, etc.). |
| `GET` | `/analytics/partner/:id/revenue` | Partner | Retrieves monthly revenue trends. |
| `GET` | `/analytics/admin/dashboard` | Admin | Retrieves a summary of platform KPIs. |
| `GET` | `/analytics/admin/trends` | Admin | Retrieves daily and weekly platform booking trends. |
| `GET` | `/analytics/admin/top-venues` | Admin | Lists venues ranked by bookings. |

---

### 11. Tournaments (`/tournaments`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/tournaments` | Public | Lists active tournaments. |
| `POST` | `/tournaments` | Partner | Hosts a tournament at a venue. |
| `GET` | `/tournaments/:id` | Public | Retrieves tournament details and registration status. |
| `PATCH` | `/tournaments/:id` | Partner/Admin | Updates tournament properties. |
| `PATCH` | `/tournaments/:id/status` | Admin | Updates a tournament's status. |
| `POST` | `/tournaments/:id/register` | User | Registers a team for a tournament and creates a payment order. |
| `GET` | `/tournaments/:id/registrations` | Partner | Lists registrations for a tournament. |
| `GET` | `/tournaments/me` | User | Retrieves the user's tournament registrations. |

---

### 12. Content & Documents (`/content` & `/documents`)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `GET` | `/content/banners` | Public | Retrieves banners for the target app context. |
| `GET` | `/content/admin/banners` | Admin | Lists all carousel banners. |
| `POST` | `/content/admin/banners` | Admin | Creates a banner. |
| `PATCH` | `/content/admin/banners/:id` | Admin | Updates banner properties. |
| `DELETE` | `/content/admin/banners/:id` | Admin | Deletes a banner. |
| `PATCH` | `/content/admin/banners/order` | Admin | Updates the display order of banners. |
| `POST` | `/documents/presign` | Partner | Generates an AWS S3 pre-signed upload URL for document uploads. |
| `GET` | `/documents` | Partner | Lists documents uploaded by the partner. |
| `GET` | `/documents/admin/pending` | Admin | Retrieves pending KYC documents from the queue. |
| `PATCH` | `/documents/:id/status` | Admin | Approves or rejects a document. |
