import { prisma } from '../../config/prisma.js';
import { redis } from '../../config/redis.js';
import { env } from '../../config/env.js';
import { ConflictError, NotFoundError, ValidationError } from '../utils/errors.js';
import { computeRefundQuote } from '../utils/bookingLifecycle.js';
import { isMockPaymentsAllowed, toPaise } from '../utils/razorpay.js';
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

type FetchImpl = (url: string, init?: RequestInit) => Promise<{ ok: boolean; status: number; json: () => Promise<any> }>;

export interface GatewayCallResult {
  /** Transport-level outcome. Non-2xx is transported here, not thrown. */
  ok: boolean;
  status: number;
  /** Parsed body; undefined when transport failed or body unreadable. */
  body?: any;
  transportError?: string;
}

async function gatewayFetch(
  url: string, keyId: string, keySecret: string, init?: RequestInit,
  fetchImpl: FetchImpl = fetch as unknown as FetchImpl
): Promise<GatewayCallResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GATEWAY_TIMEOUT_MS);
  try {
    const response = await fetchImpl(url, {
      ...init,
      headers: {
        Authorization: `Basic ${basicAuth(keyId, keySecret)}`,
        'Content-Type': 'application/json',
        ...(init?.headers || {}),
      },
      signal: controller.signal,
    });
    let body: any;
    try {
      body = await response.json();
    } catch {
      return { ok: false, status: response.status, body: undefined };
    }
    return { ok: response.ok, status: response.status, body };
  } catch (err: any) {
    const reason = err?.name === 'AbortError' ? 'timeout' : `network:${err?.message || 'error'}`;
    return { ok: false, status: 0, body: undefined, transportError: reason };
  } finally {
    clearTimeout(timer);
  }
}

export type GatewayLookupState = 'found' | 'not_found' | 'unknown';

export interface GatewayRefundLookup {
  state: GatewayLookupState;
  items: any[];
  reason?: string;
}

/**
 * Explicit reconciliation states. A lookup FAILURE is NEVER evidence that no
 * refund exists: timeouts, network errors, non-2xx, auth errors and malformed
 * bodies all map to 'unknown', which callers must treat as "leave pending".
 */
export async function queryGatewayRefunds(
  paymentId: string, keyId: string, keySecret: string,
  fetchImpl?: FetchImpl
): Promise<GatewayRefundLookup> {
  const res = await gatewayFetch(
    `https://api.razorpay.com/v1/payments/${paymentId}/refunds`, keyId, keySecret,
    undefined, fetchImpl
  );
  if (res.transportError || res.body === undefined) {
    // Timeout, network failure, or unreadable body: outcome UNKNOWN.
    // Callers must leave the pending row alone.
    const reason = res.transportError || 'malformed-gateway-response';
    return { state: 'unknown', items: [], reason };
  }
  if (!res.ok) {
    // Non-2xx on a read-only list call carries no refund evidence either way.
    return { state: 'unknown', items: [], reason: `gateway-http-${res.status}` };
  }
  const items = res.body?.items;
  if (!Array.isArray(items)) {
    return { state: 'unknown', items: [], reason: 'malformed-gateway-response' };
  }
  if (items.length === 0) {
    return { state: 'not_found', items: [] };
  }
  return { state: 'found', items };
}

export type RefundCreationDecision =
  | { outcome: 'success'; refundId: string }
  | { outcome: 'pending-confirmation'; refundId: string }
  | { outcome: 'rejected'; reason: string }
  | { outcome: 'unknown'; reason: string };

/**
 * Fail-closed classification of a Razorpay refund-creation response.
 * Pure + unit tested. Only an explicit processed state may become SUCCESS;
 * created/pending keep the local row PENDING with the gateway id stored;
 * only a deterministic gateway rejection (non-429/5xx + error object,
 * proving nothing was created) may become FAILED. Everything ambiguous
 * stays PENDING for webhook/reconciliation.
 */
export function classifyRefundCreationResponse(res: GatewayCallResult): RefundCreationDecision {
  if (res.transportError || res.body === undefined || res.body === null || typeof res.body !== 'object' || Array.isArray(res.body)) {
    return { outcome: 'unknown', reason: res.transportError || 'malformed-gateway-response' };
  }
  if (!res.ok) {
    if ((res.status === 429 || (res.status >= 500 && res.status <= 599))) {
      return { outcome: 'unknown', reason: `gateway-http-${res.status}` };
    }
    const gatewayError = res.body?.error?.description || res.body?.error?.code;
    if (gatewayError) {
      return { outcome: 'rejected', reason: String(gatewayError) };
    }
    return { outcome: 'unknown', reason: `gateway-http-${res.status}-ambiguous` };
  }
  const refund = res.body;
  if (!refund.id) {
    // 2xx without a refund id proves nothing either way.
    return { outcome: 'unknown', reason: 'missing-refund-id' };
  }
  const status = String(refund.status || '').toLowerCase();
  if (status === 'processed') {
    return { outcome: 'success', refundId: String(refund.id) };
  }
  if (status === 'created' || status === 'pending') {
    return { outcome: 'pending-confirmation', refundId: String(refund.id) };
  }
  if (status === 'failed') {
    return { outcome: 'rejected', reason: 'gateway-reported-failed' };
  }
  // Unrecognized status string: store the id, stay pending, reconcile later.
  return { outcome: 'pending-confirmation', refundId: String(refund.id) };
}

/** Gateway refund states this integration recognizes (processed + interim). */
const RECOGNIZED_REFUND_STATES = new Set(['created', 'pending', 'processed', 'failed']);

/**
 * Find the gateway refund matching this booking's payment (+ amount, and the
 * known refund id when we have one). Unrelated refunds never match.
 */
export function findMatchingRefund(
  items: any[],
  criteria: { paymentId: string; amountPaise: number; refundId?: string | null }
): any | null {
  for (const r of items) {
    if (!r || typeof r !== 'object') continue;
    if (r.payment_id !== criteria.paymentId) continue;
    if (!RECOGNIZED_REFUND_STATES.has(String(r.status))) continue;
    if (criteria.refundId && r.id !== criteria.refundId) continue;
    if (Number(r.amount) !== Number(criteria.amountPaise)) continue;
    return r;
  }
  return null;
}

export interface RefundTotals {
  captured: number;
  successfulRefundAmount: number;
  pendingRefundAmount: number;
  remainingRefundableAmount: number;
  requestedAmount: number;
}

/**
 * Server-side refund accounting. Partial refunds accumulate; concurrent
 * pending intents reserve their amounts; the total can never exceed capture.
 * Pure + unit tested.
 */
export function computeRefundTotals(
  capturedAmount: number,
  successAmounts: number[],
  pendingAmounts: number[],
  quotedAmount: number
): RefundTotals {
  const round2 = (n: number) => Math.max(0, Number(Number(n).toFixed(2)));
  const successfulRefundAmount = round2(successAmounts.reduce((s, a) => s + Number(a || 0), 0));
  const pendingRefundAmount = round2(pendingAmounts.reduce((s, a) => s + Number(a || 0), 0));
  const remainingRefundableAmount = round2(Number(capturedAmount) - successfulRefundAmount - pendingRefundAmount);
  const requestedAmount = Math.min(round2(quotedAmount), remainingRefundableAmount);
  return { captured: round2(capturedAmount), successfulRefundAmount, pendingRefundAmount, remainingRefundableAmount, requestedAmount };
}

export type StaleRecoveryDecision =
  | { action: 'adopt'; refundId: string; status: 'processed' | 'pending' | 'created' }
  | { action: 'supersede' }
  | { action: 'wait'; reason: string };

/**
 * Pure decision for a stale pending intent given a gateway lookup result.
 * 'unknown' (timeout/500/malformed) ALWAYS waits — never fails the row,
 * never triggers a fresh gateway call. Unit tested.
 */
export function decideStaleRecovery(
  lookup: GatewayRefundLookup,
  pending: { amount: number; razorpay_payment_id?: string | null },
  criteria: { paymentId: string; amountPaise: number }
): StaleRecoveryDecision {
  if (lookup.state === 'unknown') {
    return { action: 'wait', reason: lookup.reason || 'gateway-unknown' };
  }
  if (lookup.state === 'not_found') {
    return { action: 'supersede' };
  }
  const match = findMatchingRefund(lookup.items, {
    paymentId: criteria.paymentId,
    amountPaise: criteria.amountPaise,
    refundId: pending.razorpay_payment_id ?? undefined,
  });
  if (!match) {
    return { action: 'supersede' };
  }
  if (match.status === 'processed') {
    return { action: 'adopt', refundId: String(match.id), status: 'processed' };
  }
  if (match.status === 'pending' || match.status === 'created') {
    return { action: 'wait', reason: 'gateway-still-processing' };
  }
  // Gateway-side failure: safe to supersede and retry fresh.
  return { action: 'supersede' };
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
  reason?: string;
}

/**
 * P2-3 truthful refunds with a durable lifecycle.
 *
 *   requested -> PENDING (durable intent row) -> gateway -> SUCCESS | FAILED
 *                                              webhook -> SUCCESS | FAILED
 *
 * Correctness is database-held, never Redis-held:
 * - A partial unique index allows exactly ONE pending refund intent per
 *   booking, so concurrent requests converge even across restarts/instances.
 * - Stale pending intents are reconciled against an EXPLICIT gateway lookup
 *   state machine (found / not_found / unknown). 'unknown' never fails the
 *   row and never triggers a fresh gateway call.
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

  const quote = computeRefundQuote(
    booking.online_amount, booking.convenience_fee,
    (booking.slot as any)?.date, (booking.slot as any)?.start_time, now
  );
  if (quote.amount <= 0) {
    throw new ValidationError(`Refund not eligible (${quote.eligibility})`);
  }

  // Serialize the decision phase in Postgres so concurrent requests (even
  // across instances / Redis outages) share one outcome. $queryRaw
  // parameterizes the booking id (never interpolate request input into SQL).
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext('refund:' || ${req.bookingId}))`;

    // Totals INSIDE the lock: pending intents reserve their amounts, so two
    // concurrent partial refunds can never collectively exceed capture.
    const [successRows, pendingRows] = await Promise.all([
      tx.transaction.findMany({
        where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'success' },
        select: { amount: true },
      }),
      tx.transaction.findMany({
        where: { booking_id: req.bookingId, txn_type: 'refund', txn_status: 'pending' },
        select: { txn_id: true, amount: true, created_at: true, razorpay_payment_id: true },
      }),
    ]);
    const totals = computeRefundTotals(
      Number(booking.online_amount),
      successRows.map((r) => Number(r.amount)),
      pendingRows.map((r) => Number(r.amount)),
      Number(quote.amount.toFixed(2))
    );
    if (totals.remainingRefundableAmount <= 0) {
      throw new ConflictError('Booking already fully refunded', 'ALREADY_REFUNDED');
    }
    if (totals.requestedAmount <= 0) {
      throw new ConflictError('Booking already fully refunded', 'ALREADY_REFUNDED');
    }
    const amount = totals.requestedAmount;

    const freshPending = pendingRows.filter(
      (r: any) => now.getTime() - new Date(r.created_at).getTime() < PENDING_STALE_MS
    );
    if (freshPending.length > 0) {
      const row = freshPending.sort(
        (a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      )[0];
      return { duplicate: true, inFlight: true, refundTxn: row, amount: Number(row.amount), eligibility: quote.eligibility, gateway: 'razorpay', status: 'in_flight', reason: 'pending-intent-active' } as RefundOutcome;
    }

    const stalePending = pendingRows
      .filter((r: any) => now.getTime() - new Date(r.created_at).getTime() >= PENDING_STALE_MS)
      .sort((a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())[0] as any;
    if (stalePending) {
      // Reconcile BEFORE any new gateway call. 'unknown' returns in-flight
      // WITHOUT failing the row and WITHOUT a fresh call (see helper).
      const recovered = await reconcileStalePending(tx as any, stalePending, paymentId, mockPayment, quote.eligibility);
      if (recovered) return recovered;
    }

    // Durable intent first; gateway call happens after commit (see below).
    // Exactly one pending intent per booking is enforced by the partial
    // unique index; losers get P2002 and converge on the winner.
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
        return { duplicate: true, inFlight: true, refundTxn: winner, amount: Number(winner?.amount ?? amount), eligibility: quote.eligibility, gateway: 'razorpay', status: 'in_flight', reason: 'pending-intent-active' } as RefundOutcome;
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
 * Reconcile a stale pending intent. Returns an outcome when the stale row
 * resolves the request, or null when the caller may proceed to a fresh
 * intent. Gateway uncertainty ('unknown') NEVER fails the row.
 */
async function reconcileStalePending(
  tx: any, pendingRow: any, paymentId: string, mockPayment: boolean, eligibility: string
): Promise<RefundOutcome | null> {
  if (mockPayment) {
    // Mock gateway has no list API and can never have succeeded externally;
    // supersede deterministically (no lookup to misinterpret). Conditional
    // so a concurrent finalizer winning first converges instead of clobbering.
    const superseded = await tx.transaction.updateMany({
      where: { txn_id: pendingRow.txn_id, txn_status: 'pending' },
      data: { txn_status: 'failed' },
    });
    if (superseded.count === 0) {
      return convergeOnRefundWinner(tx, pendingRow, eligibility);
    }
    return null;
  }
  const { keyId, keySecret } = await resolveRazorpayKeys().catch(() => ({ keyId: '', keySecret: '' }));
  if (!keyId || !keySecret) return null; // cannot reconcile; leave pending for retry
  const lookup = await queryGatewayRefunds(paymentId, keyId, keySecret);
  const decision = decideStaleRecovery(
    lookup, pendingRow,
    { paymentId, amountPaise: toPaise(Number(pendingRow.amount)) }
  );
  if (decision.action === 'wait') {
    return {
      duplicate: true, inFlight: true, refundTxn: pendingRow,
      amount: Number(pendingRow.amount), eligibility, gateway: 'razorpay',
      status: 'in_flight', reason: decision.reason,
    };
  }
  if (decision.action === 'adopt') {
    // Conditional: a concurrent webhook may have finalized the row first.
    const adoptedMove = await tx.transaction.updateMany({
      where: { txn_id: pendingRow.txn_id, txn_status: 'pending' },
      data: { razorpay_payment_id: decision.refundId, txn_status: 'success' },
    });
    if (adoptedMove.count === 0) {
      return convergeOnRefundWinner(tx, pendingRow, eligibility);
    }
    const adopted = await tx.transaction.findUnique({ where: { txn_id: pendingRow.txn_id } });
    return { duplicate: true, refundTxn: adopted, amount: Number(adopted.amount), eligibility: 'RECONCILED', gateway: 'razorpay', status: 'duplicate' };
  }
  // 'supersede': the stale intent provably moved no money — fail it so a
  // fresh attempt starts clean. Conditional on still-pending (a concurrent
  // webhook may have finalized it; then converge on the winner instead).
  const superseded = await tx.transaction.updateMany({
    where: { txn_id: pendingRow.txn_id, txn_status: 'pending' },
    data: { txn_status: 'failed' },
  });
  if (superseded.count === 0) {
    return convergeOnRefundWinner(tx, pendingRow, eligibility);
  }
  return null;
}

/** Shared convergence: report the winning refund row instead of clobbering. */
async function convergeOnRefundWinner(tx: any, pendingRow: any, eligibility: string): Promise<RefundOutcome> {
  const winner = await tx.transaction.findFirst({
    where: { booking_id: pendingRow.booking_id, txn_type: 'refund', txn_status: { in: ['pending', 'success'] } },
    orderBy: { created_at: 'desc' },
  });
  if (winner?.txn_status === 'success') {
    return { duplicate: true, refundTxn: winner, amount: Number(winner.amount), eligibility: 'ALREADY_REFUNDED', gateway: 'razorpay', status: 'duplicate' };
  }
  return { duplicate: true, inFlight: true, refundTxn: winner ?? pendingRow, amount: Number(winner?.amount ?? pendingRow.amount), eligibility, gateway: 'razorpay', status: 'in_flight', reason: 'pending-intent-active' };
}

/**
 * Drive a committed pending intent with fail-closed creation semantics:
 * - processed  -> SUCCESS (gateway id stored)
 * - created/pending (or unrecognized status with an id) -> store the id,
 *   REMAIN PENDING; webhook/reconciliation confirms later
 * - deterministic rejection -> FAILED
 * - timeout/network/5xx/429/malformed -> REMAIN PENDING, retryable error
 *
 * The final DB write is conditional on still-pending, so a concurrent
 * webhook finalizer winning first makes this path converge instead of
 * clobbering. deps is a test seam (defaults to production modules).
 */
export async function driveRefundIntent(
  intent: any, amount: number, paymentId: string, mockPayment: boolean,
  capture: any, booking: any, quote: { eligibility: string },
  deps?: { fetchImpl?: FetchImpl; db?: any; notifier?: typeof notifyUser; keys?: { keyId: string; keySecret: string } }
): Promise<RefundOutcome> {
  const db = deps?.db ?? prisma;
  const notifier = deps?.notifier ?? notifyUser;
  const fetchImpl = deps?.fetchImpl;
  // Best-effort single-flight hint (correctness does not depend on it).
  await redis.set(REFUND_GUARD_KEY(booking.booking_id), '1', { NX: true, EX: 300 }).catch(() => undefined);
  try {
    let refundId: string;
    let gateway: 'razorpay' | 'mock' = 'razorpay';
    let pendingConfirmation = false;
    if (mockPayment) {
      if (!isMockPaymentsAllowed()) {
        await db.transaction.updateMany({
          where: { txn_id: intent.txn_id, txn_status: 'pending' },
          data: { txn_status: 'failed' },
        });
        throw new ValidationError('No refundable payment for this booking');
      }
      gateway = 'mock';
      refundId = `rfnd_mock_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
    } else {
      const { keyId, keySecret } = deps?.keys ?? await resolveRazorpayKeys();
      if (!keyId || !keySecret) {
        throw new ValidationError('Refund gateway is not configured; booking flagged for manual refund');
      }
      const res = await gatewayFetch(
        `https://api.razorpay.com/v1/payments/${paymentId}/refunds`,
        keyId, keySecret,
        { method: 'POST', body: JSON.stringify({ amount: toPaise(amount) }) },
        fetchImpl
      );
      const decision = classifyRefundCreationResponse(res);
      if (decision.outcome === 'unknown') {
        // Ambiguous outcome: row stays PENDING for retry/reconciliation.
        throw new ValidationError(
          `Refund gateway outcome unknown (${decision.reason}); request recorded, please retry`
        );
      }
      if (decision.outcome === 'rejected') {
        await db.transaction.updateMany({
          where: { txn_id: intent.txn_id, txn_status: 'pending' },
          data: { txn_status: 'failed' },
        });
        throw new ValidationError(`Refund rejected by gateway (${decision.reason}); please retry or contact support`);
      }
      refundId = decision.refundId;
      pendingConfirmation = decision.outcome === 'pending-confirmation';
    }

    // Conditional transition: only this intent row, only while still pending.
    // A concurrent webhook/finalizer winning first makes this a no-op.
    const targetStatus = pendingConfirmation ? 'pending' : 'success';
    const claimed = await db.transaction.updateMany({
      where: { txn_id: intent.txn_id, txn_status: 'pending' },
      data: { razorpay_payment_id: refundId, txn_status: targetStatus },
    });
    const refundTxn = await db.transaction.findUnique({ where: { txn_id: intent.txn_id } });

    await notifier(
      booking.user_id, 'refund',
      'Refund Processed',
      `Refund of ₹${amount} for booking ${booking.booking_id} has been initiated.`,
      `refund:${booking.booking_id}:${refundId}`
    ).catch(() => undefined);

    return {
      duplicate: claimed.count !== 1,
      refundTxn, amount, eligibility: quote.eligibility, gateway,
      status: pendingConfirmation ? 'initiated' : 'succeeded',
    };
  } finally {
    await redis.del(REFUND_GUARD_KEY(booking.booking_id)).catch(() => undefined);
  }
}

/**
 * P2-3 refund webhook events with strict transition rules:
 * - processed: pending -> success only (refund/payment/amount binding).
 * - failed: pending -> failed only.
 * - success rows are immutable; unknown ids fabricate nothing.
 *
 * SECURITY BOUNDARY: the HMAC signature over the raw body (verified in the
 * webhook route layer before this function runs) authenticates the event.
 * On top of that, paymentId is MANDATORY here and must match the booking's
 * success capture: a refund event that cannot be bound to the exact
 * (booking, payment) pair is rejected without mutating anything. Razorpay
 * refund entities always carry payment_id in this integration's contract
 * (see the parser in client.service.ts); a missing id fails closed and the
 * row remains pending for list-API reconciliation.
 */
export async function applyRefundWebhookEvent(event: {
  type: string;
  refundId?: string;
  paymentId?: string;
  amountPaise?: number;
}, db: any = prisma): Promise<{ processed: boolean; reason: string }> {
  if (!event.refundId) return { processed: false, reason: 'missing-refund-id' };
  if (!event.paymentId) return { processed: false, reason: 'payment-binding-missing' };
  const txn = await db.transaction.findFirst({
    where: { razorpay_payment_id: event.refundId, txn_type: 'refund' },
  });
  if (event.type === 'refund.processed' || event.type === 'refund.failed') {
    if (!txn) return { processed: false, reason: 'unknown-refund' };
    // Payment binding: the refund must belong to the booking's capture.
    const capture = await db.transaction.findFirst({
      where: { booking_id: (txn as any).booking_id, txn_type: 'capture', txn_status: 'success' },
    });
    if (!capture || capture.razorpay_payment_id !== event.paymentId) {
      return { processed: false, reason: 'payment-mismatch' };
    }
    if (txn.txn_status === 'success') return { processed: true, reason: 'duplicate' };
    if (txn.txn_status !== 'pending') return { processed: true, reason: 'terminal-state-kept' };
  }
  if (event.type === 'refund.processed') {
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
    const moved = await db.transaction.updateMany({
      where: { txn_id: txn.txn_id, txn_status: 'pending' },
      data: { txn_status: 'failed' },
    });
    return { processed: moved.count === 1, reason: moved.count === 1 ? 'marked-failed' : 'duplicate' };
  }
  return { processed: false, reason: 'unsupported-event' };
}
