import { prisma } from '../../config/prisma.js';
import { BOOKING_STATUS, canTransitionBooking } from '../utils/bookingLifecycle.js';
import { resolveFailedPaymentTransition } from '../utils/bookingPrivacy.js';
import { rollbackCouponForBooking } from './coupons.js';

/**
 * `payment.failed` settlement (Razorpay webhook).
 *
 * Guarantees:
 * - the transaction ledger only moves `pending -> failed`; a transaction that
 *   already settled as `success` (a concurrent payment.captured won) is never
 *   downgraded;
 * - the booking is released ONLY through a conditional PENDING -> CANCELLED
 *   transition, so CONFIRMED / CANCELLED / EXPIRED / COMPLETED bookings are
 *   never modified;
 * - the slot is released ONLY by the caller that performed the
 *   PENDING -> CANCELLED flip, and only while the slot is still `booked`,
 *   so a slot can never be released twice;
 * - repeat deliveries are idempotent: the second run performs zero writes
 *   (the transaction is already `failed`, the booking is no longer PENDING).
 */
export interface FailedPaymentReleaseResult {
  /** Whether THIS call performed the PENDING -> CANCELLED transition. */
  released: boolean;
  /** Whether THIS call flipped the slot back to available. */
  slotReleased: boolean;
  /** Booking status after processing (null when the booking is missing). */
  bookingStatus: string | null;
  /** Machine-readable reason for auditing/tests. */
  reason: string;
  booking?: any;
  slot?: any;
}

export async function releaseBookingOnFailedPayment(
  bookingId: string,
  txnId: string,
  paymentId?: string,
  db: any = prisma
): Promise<FailedPaymentReleaseResult> {
  const txn = await db.transaction.findUnique({ where: { txn_id: txnId } });
  if (!txn) {
    return { released: false, slotReleased: false, bookingStatus: null, reason: 'unknown-transaction' };
  }

  const booking = await db.booking.findUnique({
    where: { booking_id: bookingId },
    include: { venue: true },
  });
  if (!booking) {
    return { released: false, slotReleased: false, bookingStatus: null, reason: 'unknown-booking' };
  }

  const decision = resolveFailedPaymentTransition(booking.status, txn.txn_status);

  // Ledger first, and only `pending -> failed`: a settled success (captured
  // payment / verified booking) is authoritative and is never overwritten.
  await db.transaction.updateMany({
    where: { txn_id: txnId, txn_status: 'pending' },
    data: {
      txn_status: 'failed',
      ...(paymentId ? { razorpay_payment_id: paymentId } : {}),
    },
  });

  if (decision.action !== 'release') {
    return { released: false, slotReleased: false, bookingStatus: booking.status, reason: decision.reason };
  }
  if (!canTransitionBooking(BOOKING_STATUS.PENDING, BOOKING_STATUS.CANCELLED)) {
    // Defensive: the lifecycle state machine must always allow this edge.
    return { released: false, slotReleased: false, bookingStatus: booking.status, reason: 'illegal-transition' };
  }

  const outcome = await db.$transaction(async (tx: any) => {
    const flipped = await tx.booking.updateMany({
      where: { booking_id: bookingId, status: BOOKING_STATUS.PENDING },
      data: { status: BOOKING_STATUS.CANCELLED, expires_at: null },
    });
    let slotReleased = false;
    if (flipped.count > 0) {
      const slotUpdate = await tx.slot.updateMany({
        where: { slot_id: booking.slot_id, status: 'booked' },
        data: { status: 'available' },
      });
      slotReleased = slotUpdate.count > 0;
    }
    return { released: flipped.count > 0, slotReleased };
  });

  if (!outcome.released) {
    const current = await db.booking.findUnique({ where: { booking_id: bookingId } });
    console.warn(
      `payment.failed could not release booking ${bookingId}: concurrent writer set status ${current?.status ?? 'unknown'}.`
    );
    return {
      released: false,
      slotReleased: false,
      bookingStatus: current?.status ?? booking.status,
      reason: 'release-race-lost',
    };
  }

  // Best-effort, idempotent: give the coupon claim back so the athlete can
  // rebook. Reported upstream, never blocks the release itself.
  try {
    await rollbackCouponForBooking(bookingId, db);
  } catch (err: any) {
    console.warn(`Coupon rollback after failed payment skipped for ${bookingId}: ${err?.message || err}`);
  }

  const freshBooking = await db.booking.findUnique({
    where: { booking_id: bookingId },
    include: { venue: true },
  });
  const freshSlot = await db.slot.findUnique({ where: { slot_id: booking.slot_id } });

  return {
    released: true,
    slotReleased: outcome.slotReleased,
    bookingStatus: BOOKING_STATUS.CANCELLED,
    reason: decision.reason,
    booking: freshBooking ?? { ...booking, status: BOOKING_STATUS.CANCELLED },
    slot: freshSlot ?? null,
  };
}
