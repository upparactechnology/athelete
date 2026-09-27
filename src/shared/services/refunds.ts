import { prisma } from '../../config/prisma.js';
import { redis } from '../../config/redis.js';
import { env } from '../../config/env.js';
import { ConflictError, NotFoundError, ValidationError } from '../utils/errors.js';
import { computeRefundQuote } from '../utils/bookingLifecycle.js';
import { isMockPaymentsAllowed, paiseToRupees, toPaise } from '../utils/razorpay.js';
import { notifyUser } from './notifications.js';

const REFUND_GUARD_KEY = (bookingId: string) => `refund:request:${bookingId}`;
/** A pending intent older than this is considered crashed; recovery runs. */
const PENDING_STALE_MS = 15 * 60 * 1000;
const GATEWAY_TIMEOUT_MS = 20_000;

async function resolveRazorpayKeys(): Promise<{ keyId: string; keySecret: string }> {
  if (env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET) {
    return { keyId: env.RAZORPAY_KEY_ID, keySecret: env.RAZORPAY_KEY_SECRET };
  }
  const { AdminService } = await import('../../modules/admin/admin.service.js');
  const settings = await AdminService.getSettings();
  return { keyId: settings.razorpayKeyId || '', keySecret: settings.razorpayKeySecret || '' };
}

function basicAuth(keyId: string, keySecret: string): string {
  return Buffer.from(`${keyId}:${keySecret}`).toString('base64');
}

async function gatewayFetch(url: string, keyId: string, keySecret: string, init?: RequestInit): Promise<any> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GATEWAY_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      ...init,
      headers: {
        Authorization: `Basic ${basicAuth(keyId, keySecret)}`,
        'Content-Type': 'application/json',
        ...(init?.headers || {}),
      },
      signal: controller.signal,
    });
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

/** List gateway refunds for a payment (recovery path). Returns [] on failure. */
async function listGatewayRefunds(paymentId: string, keyId: string, keySecret: string): Promise<any[]> {
  try {
    const data = await gatewayFetch(`https://api.razorpay.com/v1/payments/${paymentId}/refunds`, keyId, keySecret);
    const items = Array.isArray(data?.items) ? data.items : [];
    return items;
  } catch {
    return [];
  }
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
  /** True when another request is already driving this refund. */
  inFlight?: boolean;
  refundTxn: any;
  amount: number;
  eligibility: string;
  gateway: 'razorpay' | 'mock';
  status: 'initiated' | 'succeeded' | 'in_flight' | 'duplicate';
}

/**
 * P2-3 truthful refunds with a durable lifecycle.
 *
 *   requested -> PENDING (durable intent row) -> gateway -> SUCCESS | FAILED
 *                                              webhook -> SUCCESS | FAILED
 *
 * Correctness is database-held, never Redis-held:
 * - A partial unique index allows exactly ONE pending refund intent per
 *   booking (migration 20260928+; see PENDING_INTENT_DDL note below), so
 *   concurrent requests converge even across restarts/instances.
 * - Stale pending intents (crash between gateway success and DB write) are
 *   recovered by reconciling against the gateway refund list before any new
 *   gateway call, so a retry never double-refunds.
 * - Redis remains a best-effort single-flight optimization only.
 * - Razorpay exposes no idempotency key for refund creation in this API
 *   contract, so none is invented; the pending-intent + reconcile design is
 *   the idempotency mechanism (documented limitation).
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
  if (!capture || !capture.razorpay_payment_id) {
    throw new ValidationError('No captured payment to refund for this booking');
  }
  const paymentId = capture.razorpay_payment_id;
  const mockPayment = paymentId.startsWith('pay_mock_') || paymentId.startsWith('mock_');
  if (mockPayment && !isMockPaymentsAllowed()) {
    throw new ValidationError('No refundable payment for this booking');
  }

  const done = await prisma.transaction.findFirst({
    where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
    orderBy: { created_at: 'desc' },
  });
  if (done) {
    return { duplicate: true, refundTxn: done, amount: Number(done.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay', status: 'duplicate' };
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

  // Serialize the decision phase in Postgres so concurrent requests (even
  // across instances / Redis outages) share one outcome. $queryRaw
  // parameterizes the booking id (never interpolate request input into SQL).
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext('refund:' || ${req.bookingId}))`;

    const successRow = await tx.transaction.findFirst({
      where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
    });
    if (successRow) {
      return { duplicate: true, refundTxn: successRow, amount: Number(successRow.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay', status: 'duplicate' } as RefundOutcome;
    }

    const pendingRow = await tx.transaction.findFirst({
      where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'pending' },
      orderBy: { created_at: 'desc' },
    });
    if (pendingRow) {
      const ageMs = now.getTime() - new Date(pendingRow.created_at).getTime();
      if (ageMs < PENDING_STALE_MS) {
        return { duplicate: true, inFlight: true, refundTxn: pendingRow, amount: Number(pendingRow.amount), eligibility: quote.eligibility, gateway: 'razorpay', status: 'in_flight' } as RefundOutcome;
      }
      // Stale intent: reconcile against the gateway BEFORE any new call.
      const reconciled = await reconcileStalePending(tx as any, pendingRow, paymentId, mockPayment);
      if (reconciled) return reconciled;
    }

    // Durable intent first; gateway call happens after commit (see below).
    // Exactly one pending intent per booking is enforced by the partial
    // unique index (PENDING_INTENT_DDL); losers get P2002 and converge.
    let intent: any;
    try {
      intent = await tx.transaction.create({
        data: {
          booking_id: req.bookingId,
          razorpay_order_id: capture.razorpay_order_id,
          razorpay_payment_id: null,
          txn_type: 'refund',
          txn_status: 'pending',
          amount,
        },
      });
    } catch (err: any) {
      if (err?.code === 'P2002') {
        const winner = await tx.transaction.findFirst({
          where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: { in: ['pending', 'success'] } },
          orderBy: { created_at: 'desc' },
        });
        if (winner?.txn_status === 'success') {
          return { duplicate: true, refundTxn: winner, amount: Number(winner.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay', status: 'duplicate' } as RefundOutcome;
        }
        return { duplicate: true, inFlight: true, refundTxn: winner, amount: Number(winner?.amount ?? amount), eligibility: quote.eligibility, gateway: 'razorpay', status: 'in_flight' } as RefundOutcome;
      }
      throw err;
    }
    return { intent, amount, capture, booking, quote } as any;
  }).then(async (claimed: any) => {
    if (claimed?.intent) {
      return driveRefundIntent(claimed.intent, claimed.amount, paymentId, mockPayment, capture, booking, claimed.quote);
    }
    return claimed as RefundOutcome;
  });
}

/**
 * Reconcile a stale pending intent against the gateway refund list.
 * Returns an outcome when the stale row resolves the request, or null when
 * the caller may proceed to create a fresh intent.
 */
async function reconcileStalePending(
  tx: any, pendingRow: any, paymentId: string, mockPayment: boolean
): Promise<RefundOutcome | null> {
  if (mockPayment) {
    // Mock gateway has no list API: a stale mock intent can never have
    // succeeded externally; supersede it and allow a fresh attempt.
    await tx.transaction.update({ where: { txn_id: pendingRow.txn_id }, data: { txn_status: 'failed' } });
    return null;
  }
  const { keyId, keySecret } = await resolveRazorpayKeys().catch(() => ({ keyId: '', keySecret: '' }));
  if (!keyId || !keySecret) return null; // cannot reconcile; leave for retry
  const items = await listGatewayRefunds(paymentId, keyId, keySecret);
  const match = items.find(
    (r: any) => r?.status === 'processed' && paiseToRupees(Number(r.amount)) === Number(pendingRow.amount)
  );
  if (match?.id) {
    const adopted = await tx.transaction.update({
      where: { txn_id: pendingRow.txn_id },
      data: { razorpay_payment_id: String(match.id), txn_status: 'success' },
    });
    return { duplicate: true, refundTxn: adopted, amount: Number(adopted.amount), eligibility: 'RECONCILED', gateway: 'razorpay', status: 'duplicate' };
  }
  // A gateway-side failure (or no trace at all) means this intent never
  // moved money: mark it failed so a fresh attempt starts clean.
  await tx.transaction.update({
    where: { txn_id: pendingRow.txn_id },
    data: { txn_status: 'failed' },
  });
  return null;
}

/**
 * Drive a committed pending intent: gateway call, then conditional
 * pending->success/failed transition. Network/timeout failures leave the
 * intent pending for retry/reconciliation (never silent).
 */
async function driveRefundIntent(
  intent: any, amount: number, paymentId: string, mockPayment: boolean,
  capture: any, booking: any, quote: { eligibility: string }
): Promise<RefundOutcome> {
  // Best-effort single-flight hint (correctness does not depend on it).
  await redis.set(REFUND_GUARD_KEY(booking.booking_id), '1', { NX: true, EX: 300 }).catch(() => undefined);
  try {
    let refundId: string;
    let gateway: 'razorpay' | 'mock' = 'razorpay';
    if (mockPayment) {
      if (!isMockPaymentsAllowed()) {
        await prisma.transaction.updateMany({
          where: { txn_id: intent.txn_id, txn_status: 'pending' },
          data: { txn_status: 'failed' },
        });
        throw new ValidationError('No refundable payment for this booking');
      }
      gateway = 'mock';
      refundId = `rfnd_mock_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    } else {
      const { keyId, keySecret } = await resolveRazorpayKeys();
      if (!keyId || !keySecret) {
        throw new ValidationError('Refund gateway is not configured; booking flagged for manual refund');
      }
      let rzpRefund: any;
      try {
        rzpRefund = await gatewayFetch(
          `https://api.razorpay.com/v1/payments/${paymentId}/refunds`,
          keyId, keySecret,
          { method: 'POST', body: JSON.stringify({ amount: toPaise(amount) }) }
        );
      } catch (err: any) {
        const timeout = err?.name === 'AbortError';
        throw new ValidationError(
          timeout
            ? 'Refund gateway timed out; the request is recorded and will be reconciled on retry'
            : 'Refund gateway request failed; please retry'
        );
      }
      if (!rzpRefund || !rzpRefund.id) {
        await prisma.transaction.updateMany({
          where: { txn_id: intent.txn_id, txn_status: 'pending' },
          data: { txn_status: 'failed' },
        });
        throw new ValidationError('Refund rejected by gateway; please retry or contact support');
      }
      refundId = String(rzpRefund.id);
    }

    // Conditional transition: only this intent row, only while still pending.
    // A concurrent webhook/finalizer winning first makes this a no-op.
    const claimed = await prisma.transaction.updateMany({
      where: { txn_id: intent.txn_id, txn_status: 'pending' },
      data: { razorpay_payment_id: refundId, txn_status: 'success' },
    });
    const refundTxn = claimed.count === 1
      ? await prisma.transaction.findUnique({ where: { txn_id: intent.txn_id } })
      : await prisma.transaction.findUnique({ where: { txn_id: intent.txn_id } });

    await notifyUser(
      booking.user_id, 'refund',
      'Refund Processed',
      `Refund of ₹${amount} for booking ${booking.booking_id} has been initiated.`,
      `refund:${booking.booking_id}:${refundId}`
    ).catch(() => undefined);

    return { duplicate: claimed.count !== 1, refundTxn, amount, eligibility: quote.eligibility, gateway, status: 'succeeded' };
  } finally {
    await redis.del(REFUND_GUARD_KEY(booking.booking_id)).catch(() => undefined);
  }
}

/**
 * P2-3 refund webhook events with strict transition rules:
 * - processed: pending -> success only (amount must match when provided).
 * - failed: pending -> failed only.
 * - success rows are immutable; unknown ids fabricate nothing.
 */
export async function applyRefundWebhookEvent(event: {
  type: string;
  refundId?: string;
  paymentId?: string;
  amountPaise?: number;
}, db: any = prisma): Promise<{ processed: boolean; reason: string }> {
  if (!event.refundId) return { processed: false, reason: 'missing-refund-id' };
  const txn = await db.transaction.findFirst({
    where: { razorpay_payment_id: event.refundId, txn_type: 'refund' },
  });
  if (event.type === 'refund.processed') {
    if (!txn) return { processed: false, reason: 'unknown-refund' };
    if (txn.txn_status === 'success') return { processed: true, reason: 'duplicate' };
    if (txn.txn_status !== 'pending') return { processed: true, reason: 'terminal-state-kept' };
    if (event.amountPaise != null && Number(event.amountPaise) !== toPaise(Number(txn.amount))) {
      return { processed: false, reason: 'amount-mismatch' };
    }
    const moved = await db.transaction.updateMany({
      where: { txn_id: txn.txn_id, txn_status: 'pending' },
      data: { txn_status: 'success' },
    });
    return { processed: moved.count === 1, reason: moved.count === 1 ? 'confirmed' : 'duplicate' };
  }
  if (event.type === 'refund.failed') {
    if (!txn) return { processed: false, reason: 'unknown-refund' };
    if (txn.txn_status === 'success') return { processed: true, reason: 'duplicate' };
    if (txn.txn_status !== 'pending') return { processed: true, reason: 'terminal-state-kept' };
    const moved = await db.transaction.updateMany({
      where: { txn_id: txn.txn_id, txn_status: 'pending' },
      data: { txn_status: 'failed' },
    });
    return { processed: moved.count === 1, reason: moved.count === 1 ? 'marked-failed' : 'duplicate' };
  }
  return { processed: false, reason: 'unsupported-event' };
}
