# User Flows: Athlete's POV (APOV)

This document maps the user flows for the three primary user groups: Athletes, Venue Partners, and Platform Admins.

---

## 1. Athlete / User Booking Flow

This flow describes the path a customer takes to find and book a sports slot.

```mermaid
sequenceDiagram
    autonumber
    actor Athlete as Athlete (User)
    participant Client as User App (Flutter/Dart)
    participant Redis as Redis Cache
    participant API as Express API
    participant RP as Razorpay SDK

    Athlete->>Client: Open App & Select City
    Client->>API: GET /venues?city=City&sport=Sport
    API-->>Client: Returns Venues List
    Athlete->>Client: Tap Venue Card
    Client->>API: GET /venues/:id
    API-->>Client: Returns Details & Reviews
    Athlete->>Client: Select Date & Slot
    Athlete->>Client: Click "Book Now"
    Client->>API: POST /bookings (Initiate)
    Note over API,Redis: Check booking:idem & Slot Lock (Redis SET NX 15s)
    API-->>Client: Returns Booking (PENDING) + Fees Breakdown
    Athlete->>Client: Apply Coupon & Choose Online Payment
    Client->>API: POST /payments/initiate
    API-->>Client: Returns Razorpay Order Object
    Client->>RP: Launch Razorpay Checkout Modal
    RP-->>Athlete: Enter Card/UPI & Complete Payment
    RP-->>Client: Returns razorpay_payment_id & signature
    Client->>API: POST /payments/verify
    API->>API: Verify HMAC Signature & Update DB to CONFIRMED
    API->>Redis: Delete Slot Lock (slot:lock:X)
    API-->>Client: Success Status
    Client-->>Athlete: Redirect to E-Ticket Screen (QR Code)
```

### Flow Checklist:
1. **Initiate Booking**: Acquires 15-second Redis slot lock. Checks idempotency keys.
2. **Apply Coupon**: Verifies expiration dates and usage rules.
3. **Razorpay Checkout**: Launches modal overlays.
4. **Verification Webhook**: Razorpay sends webhook notifications asynchronously to confirm transactions as a fallback.
5. **Check-in**: E-Ticket displays player QR codes to check in at venues.

---

## 2. Venue Partner Onboarding & Slot Management Flow

This flow covers partner registration, KYC submission, venue listing, and slot configurations.

```mermaid
graph TD
    A[Partner App Launch] --> B[OTP Registration/Login]
    B --> C[Profile Onboarding]
    C --> D[KYC File Uploads to S3]
    D --> E{Admin Verification}
    E -- Rejected --> C
    E -- Approved --> F[Create Venue Listing]
    F --> G[8-Step Setup Wizard]
    G --> H[Create Slot Timings & Base Prices]
    H --> I[Manage Slot Grid availability]
    I --> J[Block Slots for walk-ins/maintenance]
    I --> K[Scan E-Tickets QR at Check-in]
    I --> L[View Earnings Reports & Export CSV]
```

### Flow Checklist:
1. **KYC Documents**: Uploads GST/PAN files directly to S3 bucket.
2. **Setup Wizard**: Configures name, address, hours, photos.
3. **Slot Grid**: Renders hourly checklists.
4. **Manual Blocks**: Blocks active timings (gray-striped blocks).
5. **QR Check-in**: Scans E-Ticket codes at turfs.

---

## 3. Platform Admin Governance Flow

This flow maps how admins manage compliance, approvals, and dynamic price configurations.

```mermaid
graph LN
    A[Admin Login Portal] --> B[Operations Dashboard]
    B --> C[KYC Approval Queue]
    C -->|Verify S3 files| D[Verify Partner Status]
    B --> E[Venue Moderation Panel]
    E -->|Approve / Suspend| F[Update Venue Listings]
    B --> G[Demand Tags / Surge Grid]
    G -->|Surge Modifiers +50%| H[Update Slot Rates]
    B --> I[FCM Broadcast Panel]
    I -->|Push Targeted Alerts| J[Target User Segment]
    B --> K[Disputes Management Panel]
    K -->|Process Refunds| L[Initiate Razorpay Refund]
```

### Flow Checklist:
1. **KYC Viewer**: Inspects documents in-app.
2. **Venue Status**: Approves, rejects (with reasons), or suspends listings.
3. **Surge Pricing**: Selects slots to apply surge modifiers.
4. **Refund Processing**: Approves disputes, triggering Razorpay payouts.
