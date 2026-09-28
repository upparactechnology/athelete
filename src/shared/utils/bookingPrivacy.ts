/**
 * Booking privacy helpers (B1/B2).
 *
 * Rules:
 * - NEVER return `password_hash`, refresh/security secrets, or OTP material.
 * - NEVER broadcast full Prisma user/partner/booking objects over WebSocket.
 * - Global broadcasts carry ONLY minimal scalar booking events.
 * - Richer payloads go to the affected parties via targeted emits.
 */

const FORBIDDEN_KEYS = new Set([
  'password_hash',
  'otp_hash',
  'bank_account_no',
  'bank_ifsc',
  'temp_bank_account_no',
  'temp_bank_ifsc',
  'pan_number',
  'aadhaar_number',
  'gst_number',
]);

/** Prisma select for publicly visible user info (reviews, listings). */
export const SAFE_USER_PUBLIC_SELECT = {
  user_id: true,
  name: true,
  avatar_url: true,
  city: true,
  state: true,
} as const;

/** Prisma select for a booking counterparty (partner sees player contact). */
export const SAFE_BOOKING_USER_SELECT = {
  user_id: true,
  name: true,
  email: true,
  phone_number: true,
  avatar_url: true,
} as const;

/** Prisma select for publicly visible partner info on venue listings. */
export const SAFE_PARTNER_PUBLIC_SELECT = {
  partner_id: true,
  avatar_url: true,
} as const;

function pick<T extends Record<string, any>>(obj: T | null | undefined, keys: readonly string[]): any {
  if (!obj || typeof obj !== 'object') return obj ?? null;
  const out: Record<string, any> = {};
  for (const k of keys) {
    if (k in obj) out[k] = (obj as any)[k];
  }
  return out;
}

function stripForbidden<T>(obj: T): T {
  if (!obj || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(stripForbidden) as unknown as T;
  // Value objects must pass through untouched: recursing into them with
  // Object.entries destroys them (Date -> {}, Prisma Decimal -> {s,e,d}),
  // which corrupts every sanitized booking graph (slot dates, amounts).
  if (obj instanceof Date) return obj;
  const proto = Object.getPrototypeOf(obj);
  if (proto !== Object.prototype && proto !== null) return obj;
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (FORBIDDEN_KEYS.has(k)) continue;
    out[k] = v && typeof v === 'object' ? stripForbidden(v) : v;
  }
  return out as T;
}

/** Public user card (reviews, venue details). No contact, no secrets. */
export function toPublicUser(user: any): any {
  return pick(user, ['user_id', 'name', 'avatar_url', 'city', 'state']);
}

/** Booking counterparty card (name + contact, never secrets/bank). */
export function toBookingUser(user: any): any {
  return pick(user, ['user_id', 'name', 'email', 'phone_number', 'avatar_url']);
}

/** Own profile: everything except credentials/secrets. */
export function toSelfUser(user: any): any {
  return stripForbidden(user);
}

/** Public partner card for venue listings. No bank/KYC identity fields. */
export function toPublicPartner(partner: any): any {
  return pick(partner, ['partner_id', 'avatar_url']);
}

/** Partner owner view (own profile/bank display): all except credentials. */
export function toOwnerPartner(partner: any): any {
  return stripForbidden(partner);
}

/** Admin view: all except credentials (bank/KYC needed for verification). */
export function toAdminPartner(partner: any): any {
  return stripForbidden(partner);
}

/** Recursively sanitize a booking graph for API responses. */
export function sanitizeBookingForResponse(booking: any, userMapper: (u: any) => any = toBookingUser): any {
  if (!booking || typeof booking !== 'object') return booking;
  if (Array.isArray(booking)) return booking.map((b) => sanitizeBookingForResponse(b, userMapper));
  const out: Record<string, any> = { ...booking };
  if (out.user) out.user = userMapper(out.user);
  if (out.venue && typeof out.venue === 'object') {
    const venue = { ...out.venue };
    if (venue.partner) venue.partner = toPublicPartner(venue.partner);
    out.venue = venue;
  }
  if (out.booking && typeof out.booking === 'object') {
    out.booking = sanitizeBookingForResponse(out.booking, userMapper);
  }
  return stripForbidden(out);
}

export interface BookingEventTargetedOptions {
  /** Owner/partner-only fields. Excluded from global broadcasts. */
  includePrivate?: boolean;
}

/**
 * Minimal scalar booking event safe for GLOBAL broadcast.
 * Contains IDs + status only: no names, contacts, amounts, etickets, relations.
 */
export function toBookingEvent(booking: any, opts: BookingEventTargetedOptions = {}): Record<string, any> {
  if (!booking || typeof booking !== 'object') return {};
  const event: Record<string, any> = {
    booking_id: booking.booking_id,
    venue_id: booking.venue_id,
    slot_id: booking.slot_id,
    status: booking.status,
    payment_mode: booking.payment_mode,
    created_at: booking.created_at,
  };
  if (opts.includePrivate) {
    event.user_id = booking.user_id ?? booking.user?.user_id;
    event.online_amount = booking.online_amount;
    event.venue_amount = booking.venue_amount;
    event.eticket_code = booking.eticket_code;
  }
  return event;
}

export type WebhookBookingAction =
  | 'confirm'
  | 'converge'
  | 'record_truthful'
  | 'record_mismatch'
  | 'duplicate';

export interface WebhookTransition {
  action: WebhookBookingAction;
  /** Whether the booking row may transition to CONFIRMED. */
  confirmBooking: boolean;
  /** Whether user stats/notifications side effects may run. */
  runSideEffects: boolean;
  reason: string;
}

/**
 * Pure webhook state machine (B3). Decoupled from Prisma so it is unit
 * testable without credentials:
 * - success txn + any event  -> duplicate (idempotent, no side effects)
 * - amount/currency mismatch -> record_mismatch (never confirm)
 * - PENDING + match          -> confirm (atomic PENDING->CONFIRMED + stats)
 * - CONFIRMED + match        -> converge (txn->success only, no stat double-count)
 * - any other status + match -> record_truthful (money captured; booking untouched)
 */
export type FailedPaymentAction = 'release' | 'no_op';

export interface FailedPaymentTransition {
  action: FailedPaymentAction;
  /** Whether the booking row may transition PENDING -> CANCELLED. */
  releaseBooking: boolean;
  /** Whether the held slot may be released back to available. */
  releaseSlot: boolean;
  reason: string;
}

/**
 * Pure state machine for the `payment.failed` webhook, mirroring
 * resolveWebhookTransition so failure handling is unit testable:
 * - settled (success) transaction      -> no_op (a capture already won)
 * - PENDING booking                    -> release (PENDING -> CANCELLED + slot)
 * - CONFIRMED/CANCELLED/EXPIRED/...    -> no_op (never touch settled bookings)
 *
 * The caller must still apply the transition conditionally
 * (updateMany where status = PENDING) so concurrent writers can never
 * produce CONFIRMED-after-CANCELLED or a double slot release.
 */
export function resolveFailedPaymentTransition(
  bookingStatus: string | undefined | null,
  txnStatus: string | undefined | null
): FailedPaymentTransition {
  if (txnStatus === 'success') {
    return { action: 'no_op', releaseBooking: false, releaseSlot: false, reason: 'transaction-already-success' };
  }
  if (bookingStatus === 'PENDING') {
    return { action: 'release', releaseBooking: true, releaseSlot: true, reason: 'pending-payment-failed' };
  }
  return {
    action: 'no_op',
    releaseBooking: false,
    releaseSlot: false,
    reason: `booking-not-pending:${bookingStatus ?? 'unknown'}`,
  };
}

export function resolveWebhookTransition(
  bookingStatus: string | undefined | null,
  amountOk: boolean,
  currencyOk: boolean,
  txnStatus: string | undefined | null
): WebhookTransition {
  if (txnStatus === 'success') {
    return { action: 'duplicate', confirmBooking: false, runSideEffects: false, reason: 'transaction-already-success' };
  }
  if (!amountOk || !currencyOk) {
    return { action: 'record_mismatch', confirmBooking: false, runSideEffects: false, reason: !amountOk ? 'amount-mismatch' : 'currency-mismatch' };
  }
  if (bookingStatus === 'PENDING') {
    return { action: 'confirm', confirmBooking: true, runSideEffects: true, reason: 'pending-with-matching-capture' };
  }
  if (bookingStatus === 'CONFIRMED') {
    return { action: 'converge', confirmBooking: false, runSideEffects: false, reason: 'already-confirmed' };
  }
  return { action: 'record_truthful', confirmBooking: false, runSideEffects: false, reason: `booking-not-pending:${bookingStatus ?? 'unknown'}` };
}
