# Technology Stack: Athlete's POV (APOV)

The APOV ecosystem is built using a modern full-stack JavaScript/TypeScript architecture designed for high availability, transactional integrity, and responsive performance.

---

## Technical Stack Diagram

```
 ┌────────────────────────────────────────────────────────┐
 │                      FRONTEND LAYER                    │
 │  Flutter (Dart SDK) Cross-Platform Mobile & Web Apps   │
 │  (Athlete app, Partner app, Admin portal clients)      │
 └──────────────────────────┬─────────────────────────────┘
                            │ REST API + JSON
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │                      BACKEND API                       │
 │  Node.js (v20+) Runtime + Express.js v4 Framework       │
 │  TypeScript (Strict Mode compilation)                  │
 └──────────┬────────────────────┬───────────────────┬────┘
            │                    │                   │
            ▼                    ▼                   ▼
 ┌──────────────────┐    ┌──────────────┐    ┌──────────────┐
 │   CACHE LAYER    │    │  DATABASE    │    │ INTEGRATIONS │
 │  Redis v7 (Locks)│    │ PostgreSQL 16│    │ Razorpay SDK │
 │  OTP & Cache     │    │ (Via Prisma) │    │ Firebase FCM │
 └──────────────────┘    └──────────────┘    └──────────────┘
```

---

## 1. Backend Core Stack

- **Runtime**: **Node.js (v20+)**
  - High-performance V8 execution engine using native ESM loaders.
- **Language**: **TypeScript**
  - Configured with `strict: true` flags, preventing structural type errors.
- **Web Server**: **Express.js (v4)**
  - Configured with security-hardening middleware:
    - **Helmet.js**: Sets security headers (XSS filters, Content Security Policies, HSTS).
    - **CORS**: Origin controls validated against environment configurations (`ALLOWED_ORIGINS`).
    - **Compression**: Gzip compression for API payloads.
- **Database ORM**: **Prisma ORM**
  - Maps TypeScript structures to SQL schemas. Database transactions are handled using transaction blocks.
- **Logging Engine**: **Winston Logger**
  - Formats output streams as structured JSON logs, redirecting HTTP requests (via Morgan streaming) to files and standard output.

---

## 2. Frontend Layer

- **Framework**: **Flutter (Dart SDK)**
  - Single code-base targeting iOS, Android, and responsive Web clients.
- **State Management**: **Riverpod**
  - High-performance, compile-safe dependency injection and state management.
- **API Client**: **Dio HTTP Client (`api_client.dart`)**
  - Robust networking with custom interceptors for JWT token attachment and automated 401 token refresh.
- **Secure Local Storage**: **flutter_secure_storage**
  - Hashed storage mechanisms preserving session tokens securely on physical devices.

---

## 3. Database, Caching & Queuing

- **Relational Database**: **PostgreSQL v16**
  - Configured with UUID keys (`uuid-ossp` extensions) and timezone-aware timestamps.
- **Key-Value Store**: **Redis v7**
  - Serves as the platform's concurrency controller:
    - **OTP Hash Storage**: Restricts OTP lifetime to 5 minutes.
    - **Rate Limit Caches**: Keeps count of API requests.
    - **Real-Time Slot Locks**: Uses `SET key val NX EX 15` lock keys.

---

## 4. Third-Party Services & Integrations

- **Payment Processing**: **Razorpay API SDK**
  - Manages orders, signatures, refunds, and webhook events.
- **Push Notification System**: **Firebase Admin SDK (FCM)**
  - Sends notifications to User and Partner devices.
- **KYC File Storage**: **AWS S3**
  - Partner documents are uploaded directly to S3 buckets using signed upload URLs.
