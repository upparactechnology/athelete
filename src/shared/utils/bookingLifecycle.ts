import { ConflictError, ValidationError } from './errors.js';

/**
 * P2-2 authoritative booking state machine + P2-1 expiry helpers.
 *
 * Legal transitions:
 *   PENDING   -> CONFIRMED | CANCELLED | EXPIRED
 *   CONFIRMED -> CANCELLED | COMPLETED
 * Everything else is rejected (CANCELLED/EXPIRED/COMPLETED are terminal).
 */

export const BOOKING_STATUS = {
  PENDING: 'PENDING',
  CONFIRMED: 'CONFIRMED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
  COMPLETED: 'COMPLETED',
} as const;

export type BookingStatus = (typeof BOOKING_STATUS)[keyof typeof BOOKING_STATUS];

const LEGAL_TRANSITIONS: Record<string, readonly string[]> = {
  PENDING: [BOOKING_STATUS.CONFIRMED, BOOKING_STATUS.CANCELLED, BOOKING_STATUS.EXPIRED],
  CONFIRMED: [BOOKING_STATUS.CANCELLED, BOOKING_STATUS.COMPLETED],
  CANCELLED: [],
  EXPIRED: [],
  COMPLETED: [],
};

export function canTransitionBooking(from: string | undefined | null, to: string | undefined | null): boolean {
  if (!from || !to) return false;
  return LEGAL_TRANSITIONS[from]?.includes(to) ?? false;
}

/** Throws HTTP 409 on illegal transitions. Pure + unit tested. */
export function assertBookingTransition(from: string | undefined | null, to: string | undefined | null): void {
  if (!canTransitionBooking(from, to)) {
    throw new ConflictError(
      `Illegal booking transition ${from ?? 'unknown'} -> ${to ?? 'unknown'}`,
      'ILLEGAL_STATUS_TRANSITION'
    );
  }
}

export function isTerminalBookingStatus(status: string | undefined | null): boolean {
  return status === 'CANCELLED' || status === 'EXPIRED' || status === 'COMPLETED';
}

/**
 * Refund quote — SAME policy math as the existing cancellation flow
 * (March 2026 policy: >=24h 95%, >=6h 50%, else 0). Pure + unit tested.
 * `totalPaid` preserves the existing definition (online + convenience fee).
 */
export interface RefundQuote {
  eligibility: 'FULL_REFUND' | 'PARTIAL_REFUND' | 'NO_REFUND';
  message: string;
  amount: number;
}

export function computeRefundQuote(
  onlineAmount: unknown,
  convenienceFee: unknown,
  slotDate: Date | string | null | undefined,
  slotStartTime: string | null | undefined,
  now: Date = new Date()
): RefundQuote {
  const noRefund: RefundQuote = {
    eligibility: 'NO_REFUND',
    message: 'No refund (Less than 6 hours before booking)',
    amount: 0,
  };
  if (!slotDate) return noRefund;
  let slotDateTime: Date;
  try {
    const slotDateStr = new Date(slotDate).toISOString().split('T')[0];
    const startTimeStr = slotStartTime || '00:00';
    slotDateTime = new Date(`${slotDateStr}T${startTimeStr.length === 5 ? startTimeStr + ':00' : startTimeStr}`);
    if (Number.isNaN(slotDateTime.getTime())) return noRefund;
  } catch {
    return noRefund;
  }
  const diffHours = (slotDateTime.getTime() - now.getTime()) / (1000 * 60 * 60);
  const totalPaid = Number(onlineAmount || 0) + Number(convenienceFee || 0);
  if (diffHours >= 24) {
    return {
      eligibility: 'FULL_REFUND',
      message: 'Full refund or platform credit (minus handling fee)',
      amount: Math.max(0, totalPaid * 0.95),
    };
  }
  if (diffHours >= 6) {
    return {
      eligibility: 'PARTIAL_REFUND',
      message: 'Partial refund or platform credit (minus handling fee)',
      amount: Math.max(0, totalPaid * 0.5),
    };
  }
  return noRefund;
}

/**
 * Server-side coupon discount math (moved verbatim from createBooking so the
 * claim path and tests share one implementation). Returns discount >= 0.
 */
export function computeCouponDiscount(
  coupon: { discount_type: string; discount_value: number | string; max_discount?: number | string | null } | null | undefined,
  price: number
): number {
  if (!coupon) return 0;
  let discount: number;
  if (coupon.discount_type === 'percent') {
    discount = (Number(price) * Number(coupon.discount_value)) / 100;
    if (coupon.max_discount != null) {
      discount = Math.min(discount, Number(coupon.max_discount));
    }
  } else {
    discount = Number(coupon.discount_value);
  }
  if (!Number.isFinite(discount) || discount < 0) return 0;
  return Math.min(discount, Number(price));
}

/** Tournament registration guard. Pure + unit tested. */
export function canRegisterTournament(
  status: string | undefined | null,
  currentParticipants: number,
  maxParticipants: number
): { ok: boolean; reason: string } {
  if (status !== 'upcoming' && status !== 'open') {
    return { ok: false, reason: `tournament-not-open:${status ?? 'unknown'}` };
  }
  if (!Number.isFinite(currentParticipants) || !Number.isFinite(maxParticipants)) {
    return { ok: false, reason: 'invalid-capacity' };
  }
  if (currentParticipants >= maxParticipants) {
    return { ok: false, reason: 'tournament-full' };
  }
  return { ok: true, reason: 'slot-available' };
}

/**
 * Review eligibility (P2-6). Booking must be the requester's CONFIRMED (or
 * COMPLETED) booking for the same venue. Pure + unit tested.
 */
export function isReviewEligible(
  booking: { user_id?: string; venue_id?: string; status?: string } | null | undefined,
  userId: string,
  venueId: string,
  requesterRole: string
): { ok: boolean; reason: string } {
  if (requesterRole !== 'user') return { ok: false, reason: 'only-players-may-review' };
  if (!booking) return { ok: false, reason: 'no-eligible-booking' };
  if (booking.user_id !== userId) return { ok: false, reason: 'booking-not-owned' };
  if (booking.venue_id !== venueId) return { ok: false, reason: 'venue-mismatch' };
  if (booking.status !== 'CONFIRMED' && booking.status !== 'COMPLETED') {
    return { ok: false, reason: `booking-not-completed:${booking.status ?? 'unknown'}` };
  }
  return { ok: true, reason: 'eligible' };
}

export function ensureReviewEligible(
  booking: { user_id?: string; venue_id?: string; status?: string } | null | undefined,
  userId: string,
  venueId: string,
  requesterRole: string
): void {
  const check = isReviewEligible(booking, userId, venueId, requesterRole);
  if (!check.ok) {
    throw new ValidationError(`Review not allowed (${check.reason})`);
  }
}
