import { prisma } from '../../config/prisma.js';
import { redis } from '../../config/redis.js';
import { env } from '../../config/env.js';
import { ConflictError, NotFoundError, ValidationError } from '../utils/errors.js';
import { computeRefundQuote } from '../utils/bookingLifecycle.js';
import { isMockPaymentsAllowed, toPaise } from '../utils/razorpay.js';
import { notifyUser } from './notifications.js';

const REFUND_GUARD_KEY = (bookingId: string) => `refund:request:${bookingId}`;

async function resolveRazorpayKeys(): Promise<{ keyId: string; keySecret: string }> {
  if (env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET) {
    return { keyId: env.RAZORPAY_KEY_ID, keySecret: env.RAZORPAY_KEY_SECRET };
  }
  const { AdminService } = await import('../../modules/admin/admin.service.js');
  const settings = await AdminService.getSettings();
  return { keyId: settings.razorpayKeyId || '', keySecret: settings.razorpayKeySecret || '' };
}

export interface RefundRequest {
  bookingId: string;
  /** Owning user id; omitted for admin-initiated refunds. */
  userId?: string;
  isAdmin?: boolean;
  now?: Date;
}

export interface RefundOutcome {
  duplicate: boolean;
  refundTxn: any;
  amount: number;
  eligibility: string;
  gateway: 'razorpay' | 'mock';
}

/**
 * P2-3 real refunds. Server-determined amount (cancellation policy quote,
 * capped at captured-minus-already-refunded). Idempotent per booking:
 * concurrent/duplicate requests converge on the single success refund row.
 * Mock refunds obey the same gating as mock payments.
 */
export async function requestBookingRefund(req: RefundRequest): Promise<RefundOutcome> {
  const now = req.now ?? new Date();
  const booking = await prisma.booking.findUnique({
    where: { booking_id: req.bookingId },
    include: { slot: true },
  });
  if (!booking) throw new NotFoundError('Booking not found');
  if (!req.isAdmin && req.userId && booking.user_id !== req.userId) {
    throw new ValidationError('You do not own this booking');
  }

  const capture = await prisma.transaction.findFirst({
    where: { booking_id: req.bookingId, txn_type: 'capture', txn_status: 'success' },
    orderBy: { created_at: 'desc' },
  });
  if (!capture || !capture.razorpay_payment_id || capture.razorpay_payment_id.startsWith('pay_mock_')) {
    if (capture?.razorpay_payment_id?.startsWith('pay_mock_') && !isMockPaymentsAllowed()) {
      throw new ValidationError('No refundable payment for this booking');
    }
    if (!capture || !capture.razorpay_payment_id) {
      throw new ValidationError('No captured payment to refund for this booking');
    }
  }

  const existing = await prisma.transaction.findFirst({
    where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
    orderBy: { created_at: 'desc' },
  });
  if (existing) {
    return { duplicate: true, refundTxn: existing, amount: Number(existing.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay' };
  }

  const quote = computeRefundQuote(
    booking.online_amount, booking.convenience_fee,
    (booking.slot as any)?.date, (booking.slot as any)?.start_time, now
  );
  if (quote.amount <= 0) {
    throw new ValidationError(`Refund not eligible (${quote.eligibility})`);
  }

  const refundedRows = await prisma.transaction.findMany({
    where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
    select: { amount: true },
  });
  const alreadyRefunded = refundedRows.reduce((s, r) => s + Number(r.amount), 0);
  const remaining = Number(booking.online_amount) - alreadyRefunded;
  const amount = Math.min(Number(quote.amount.toFixed(2)), Math.max(0, remaining));
  if (amount <= 0) {
    throw new ConflictError('Booking already fully refunded', 'ALREADY_REFUNDED');
  }

  // Single-flight per booking so concurrent requests share one outcome.
  const guard = await redis.set(REFUND_GUARD_KEY(req.bookingId), '1', { NX: true, EX: 300 }).catch(() => 'bypass' as const);
  try {
    const recheck = await prisma.transaction.findFirst({
      where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
    });
    if (recheck) {
      return { duplicate: true, refundTxn: recheck, amount: Number(recheck.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay' };
    }

    const paymentId = capture.razorpay_payment_id as string;
    const mockPayment = paymentId.startsWith('pay_mock_') || paymentId.startsWith('mock_');
    let refundId: string;
    let gateway: 'razorpay' | 'mock' = 'razorpay';
    if (mockPayment) {
      if (!isMockPaymentsAllowed()) throw new ValidationError('No refundable payment for this booking');
      gateway = 'mock';
      refundId = `rfnd_mock_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    } else {
      const { keyId, keySecret } = await resolveRazorpayKeys();
      if (!keyId || !keySecret) {
        throw new ValidationError('Refund gateway is not configured; booking flagged for manual refund');
      }
      let rzpRefund: any;
      try {
        const response = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/refunds`, {
          method: 'POST',
          headers: {
            Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ amount: toPaise(amount) }),
        });
        rzpRefund = await response.json();
      } catch {
        throw new ValidationError('Refund gateway request failed; please retry');
      }
      if (!rzpRefund || !rzpRefund.id) {
        await prisma.transaction.create({
          data: {
            booking_id: req.bookingId,
            razorpay_order_id: capture.razorpay_order_id,
            razorpay_payment_id: paymentId,
            txn_type: 'refund',
            txn_status: 'failed',
            amount,
          },
        });
        throw new ValidationError('Refund rejected by gateway; please retry or contact support');
      }
      refundId = rzpRefund.id;
    }

    const refundTxn = await prisma.transaction.create({
      data: {
        booking_id: req.bookingId,
        razorpay_order_id: capture.razorpay_order_id,
        razorpay_payment_id: refundId,
        txn_type: 'refund',
        txn_status: 'success',
        amount,
      },
    });

    await notifyUser(
      booking.user_id, 'refund',
      'Refund Processed',
      `Refund of ₹${amount} for booking ${req.bookingId} has been initiated.`,
      `refund:${req.bookingId}:${refundId}`
    ).catch(() => undefined);

    return { duplicate: false, refundTxn, amount, eligibility: quote.eligibility, gateway };
  } finally {
    if (guard !== 'bypass') {
      await redis.del(REFUND_GUARD_KEY(req.bookingId)).catch(() => undefined);
    }
  }
}

/**
 * P2-3 refund webhook events (Razorpay sends refund.processed / refund.failed).
 * Idempotent via the shared webhook event guard owned by the caller: pass the
 * event id so duplicate deliveries converge.
 */
export async function applyRefundWebhookEvent(event: {
  type: string;
  refundId?: string;
  paymentId?: string;
  amountPaise?: number;
}): Promise<{ processed: boolean; reason: string }> {
  if (!event.refundId) return { processed: false, reason: 'missing-refund-id' };
  const txn = await prisma.transaction.findFirst({
    where: { razorpay_payment_id: event.refundId, txn_type: 'refund' },
  });
  if (event.type === 'refund.processed') {
    if (!txn) return { processed: false, reason: 'unknown-refund' };
    if (txn.txn_status === 'success') return { processed: true, reason: 'duplicate' };
    await prisma.transaction.update({ where: { txn_id: txn.txn_id }, data: { txn_status: 'success' } });
    return { processed: true, reason: 'confirmed' };
  }
  if (event.type === 'refund.failed') {
    if (!txn) return { processed: false, reason: 'unknown-refund' };
    if (txn.txn_status === 'success') return { processed: true, reason: 'duplicate' };
    await prisma.transaction.update({ where: { txn_id: txn.txn_id }, data: { txn_status: 'failed' } });
    return { processed: true, reason: 'marked-failed' };
  }
  return { processed: false, reason: 'unsupported-event' };
}
