import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  RAZORPAY_CURRENCY,
  isMockOrderId,
  isMockPaymentId,
  isMockPaymentsAllowed,
  paiseToRupees,
  toPaise,
  verifyRazorpayPaymentSignature,
  verifyRazorpayWebhookSignature,
} from '../src/shared/utils/razorpay.js';
import { normalizeAuthRole, verifyGoogleIdToken } from '../src/shared/utils/googleAuth.js';
import { resolvePrivateFile, validateUploadedFileContent } from '../src/middleware/upload.js';

const TEST_SECRET = 'test_razorpay_key_secret_abc123';

function signPayment(orderId: string, paymentId: string, secret: string): string {
  return crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');
}

describe('P0: Razorpay payment signature', () => {
  const orderId = 'order_RZTest123456';
  const paymentId = 'pay_RZTest654321';

  it('valid signature succeeds', () => {
    expect(verifyRazorpayPaymentSignature(orderId, paymentId, signPayment(orderId, paymentId, TEST_SECRET), TEST_SECRET)).toBe(true);
  });

  it('invalid signature fails', () => {
    expect(verifyRazorpayPaymentSignature(orderId, paymentId, 'deadbeef'.repeat(8), TEST_SECRET)).toBe(false);
  });

  it('wrong order fails', () => {
    const sig = signPayment(orderId, paymentId, TEST_SECRET);
    expect(verifyRazorpayPaymentSignature('order_OTHER', paymentId, sig, TEST_SECRET)).toBe(false);
  });

  it('wrong payment fails', () => {
    const sig = signPayment(orderId, paymentId, TEST_SECRET);
    expect(verifyRazorpayPaymentSignature(orderId, 'pay_OTHER', sig, TEST_SECRET)).toBe(false);
  });

  it('wrong secret fails', () => {
    const sig = signPayment(orderId, paymentId, TEST_SECRET);
    expect(verifyRazorpayPaymentSignature(orderId, paymentId, sig, 'different-secret')).toBe(false);
  });

  it('missing fields fail (client-controlled success cannot confirm)', () => {
    expect(verifyRazorpayPaymentSignature('', paymentId, 'x'.repeat(64), TEST_SECRET)).toBe(false);
    expect(verifyRazorpayPaymentSignature(orderId, '', 'x'.repeat(64), TEST_SECRET)).toBe(false);
    expect(verifyRazorpayPaymentSignature(orderId, paymentId, '', TEST_SECRET)).toBe(false);
    expect(verifyRazorpayPaymentSignature(orderId, paymentId, signPayment(orderId, paymentId, TEST_SECRET), '')).toBe(false);
  });

  it('real-looking Razorpay ids are NOT classified as mock (old bypass regression)', () => {
    // The old code skipped verification for any id starting with "pay_",
    // which includes every genuine Razorpay payment id.
    expect(isMockPaymentId('pay_RZTest654321')).toBe(false);
    expect(isMockPaymentId('pay_mock_dev123')).toBe(true);
    expect(isMockOrderId('order_RZTest123456')).toBe(false);
    expect(isMockOrderId('order_mock_123')).toBe(true);
  });

  it('mock payments are never allowed in production', () => {
    const prevNode = process.env.NODE_ENV;
    const prevFlag = process.env.ALLOW_MOCK_PAYMENTS;
    process.env.NODE_ENV = 'production';
    process.env.ALLOW_MOCK_PAYMENTS = 'true';
    expect(isMockPaymentsAllowed()).toBe(false);
    process.env.NODE_ENV = 'test';
    process.env.ALLOW_MOCK_PAYMENTS = 'true';
    expect(isMockPaymentsAllowed()).toBe(true);
    process.env.ALLOW_MOCK_PAYMENTS = 'false';
    expect(isMockPaymentsAllowed()).toBe(false);
    process.env.NODE_ENV = prevNode;
    if (prevFlag === undefined) delete process.env.ALLOW_MOCK_PAYMENTS;
    else process.env.ALLOW_MOCK_PAYMENTS = prevFlag;
  });

  it('amount helpers are exact (paise round-trip)', () => {
    expect(toPaise(499.99)).toBe(49999);
    expect(toPaise('100')).toBe(10000);
    expect(paiseToRupees(49999)).toBe(499.99);
    expect(RAZORPAY_CURRENCY).toBe('INR');
  });
});

describe('P0: Razorpay webhook signature (raw body)', () => {
  const secret = 'whsec_test_123';
  const raw = Buffer.from(JSON.stringify({ event: 'payment.captured', id: 'evt_1' }));

  it('valid raw-body signature succeeds', () => {
    const sig = crypto.createHmac('sha256', secret).update(raw).digest('hex');
    expect(verifyRazorpayWebhookSignature(raw, sig, secret)).toBe(true);
  });

  it('tampered body fails', () => {
    const sig = crypto.createHmac('sha256', secret).update(raw).digest('hex');
    const tampered = Buffer.from(JSON.stringify({ event: 'payment.captured', id: 'evt_2' }));
    expect(verifyRazorpayWebhookSignature(tampered, sig, secret)).toBe(false);
  });

  it('missing signature or secret fails', () => {
    expect(verifyRazorpayWebhookSignature(raw, undefined, secret)).toBe(false);
    expect(verifyRazorpayWebhookSignature(raw, 'abc', undefined)).toBe(false);
  });
});

describe('P0: Google auth role handling', () => {
  it('client cannot choose privileged roles', () => {
    expect(normalizeAuthRole('admin')).toBe('user');
    expect(normalizeAuthRole('ADMIN')).toBe('user');
    expect(normalizeAuthRole(undefined)).toBe('user');
    expect(normalizeAuthRole('partner')).toBe('partner');
    expect(normalizeAuthRole('user')).toBe('user');
  });

  it('missing ID token fails without network', async () => {
    await expect(verifyGoogleIdToken('')).rejects.toMatchObject({ statusCode: 400 });
  });

  it('arbitrary email string is not a valid token', async () => {
    // Must fail verification (no Google round-trip can mint identity here).
    await expect(verifyGoogleIdToken('victim@example.com')).rejects.toMatchObject({ statusCode: 401 });
  });
});

describe('P0: upload validation', () => {
  it('private file resolution rejects path traversal', () => {
    expect(() => resolvePrivateFile('../secret.env')).toThrow();
    expect(() => resolvePrivateFile('..\\secret.env')).toThrow();
    expect(() => resolvePrivateFile('/etc/passwd')).toThrow();
    expect(resolvePrivateFile('upload-abc123.png')).toContain('upload-abc123.png');
  });

  it('magic-byte validation accepts real headers and rejects spoofed content', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'apov-upload-'));
    const jpg = path.join(dir, 'a.jpg');
    const png = path.join(dir, 'b.png');
    const pdf = path.join(dir, 'c.pdf');
    const fake = path.join(dir, 'evil.jpg');
    fs.writeFileSync(jpg, Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]));
    fs.writeFileSync(png, Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    fs.writeFileSync(pdf, Buffer.from('%PDF-1.7 test content'));
    fs.writeFileSync(fake, Buffer.from('<?php echo "pwn"; ?>'));
    expect(() => validateUploadedFileContent(jpg, 'image/jpeg')).not.toThrow();
    expect(() => validateUploadedFileContent(png, 'image/png')).not.toThrow();
    expect(() => validateUploadedFileContent(pdf, 'application/pdf')).not.toThrow();
    expect(() => validateUploadedFileContent(fake, 'image/jpeg')).toThrow();
    expect(fs.existsSync(fake)).toBe(false); // spoofed file deleted
    fs.rmSync(dir, { recursive: true, force: true });
  });
});

describe('P0: bypass removal (static regression guards)', () => {
  const serviceSrc = fs.readFileSync(
    new URL('../src/modules/client/client.service.ts', import.meta.url),
    'utf8'
  );

  it('no hard-coded OTP bypass remains', () => {
    expect(serviceSrc).not.toContain('"123456"');
    expect(serviceSrc).not.toContain("'123456'");
  });

  it('no pay_ verification skip remains', () => {
    expect(serviceSrc).not.toContain('startsWith("pay_")');
    expect(serviceSrc).not.toContain("startsWith('pay_')");
  });

  it('booking uses atomic reservation + transactions', () => {
    expect(serviceSrc).toContain('updateMany');
    expect(serviceSrc).toContain('SLOT_UNAVAILABLE');
    expect(serviceSrc).toContain('prisma.$transaction');
  });
});
