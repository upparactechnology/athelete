import crypto from 'node:crypto';

/**
 * Razorpay server-side verification helpers (P0).
 *
 * NEVER trust client-controlled payment status. Every confirmation path must
 * verify the HMAC signature and (for verify endpoints) the payment object
 * fetched from Razorpay with the server-held key secret.
 */

export const RAZORPAY_CURRENCY = 'INR';

export function isProduction(): boolean {
  return process.env.NODE_ENV === 'production';
}

/** Dev-only simulated payments require an explicit flag and never run in prod. */
export function isMockPaymentsAllowed(): boolean {
  return (
    process.env.ALLOW_MOCK_PAYMENTS === 'true' &&
    process.env.NODE_ENV !== 'production'
  );
}

export function isMockOrderId(orderId: string | undefined | null): boolean {
  if (!orderId) return false;
  return orderId.startsWith('order_mock_') || orderId.startsWith('order_wallet_mock_') || orderId.startsWith('order_') === false;
}

export function isMockPaymentId(paymentId: string | undefined | null): boolean {
  if (!paymentId) return false;
  return paymentId.startsWith('pay_mock_');
}

/**
 * Verify `razorpay_signature` = HMAC-SHA256(order_id|payment_id, key_secret)
 * using a timing-safe comparison.
 */
export function verifyRazorpayPaymentSignature(
  orderId: string,
  paymentId: string,
  signature: string,
  keySecret: string
): boolean {
  if (!orderId || !paymentId || !signature || !keySecret) return false;
  const expected = crypto
    .createHmac('sha256', keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(signature, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Verify a Razorpay webhook signature computed over the RAW request body.
 * Callers must pass the raw Buffer — never a re-stringified JSON object.
 */
export function verifyRazorpayWebhookSignature(
  rawBody: Buffer | string,
  signature: string | undefined,
  webhookSecret: string | undefined
): boolean {
  if (!signature || !webhookSecret) return false;
  const expected = crypto
    .createHmac('sha256', webhookSecret)
    .update(typeof rawBody === 'string' ? rawBody : rawBody)
    .digest('hex');
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(signature, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

export function toPaise(amountRupees: number | string): number {
  return Math.round(Number(amountRupees) * 100);
}

export function paiseToRupees(amountPaise: number | string): number {
  return Number(amountPaise) / 100;
}
