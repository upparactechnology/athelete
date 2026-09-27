import fs from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  SAFE_BOOKING_USER_SELECT,
  SAFE_PARTNER_PUBLIC_SELECT,
  SAFE_USER_PUBLIC_SELECT,
  resolveWebhookTransition,
  sanitizeBookingForResponse,
  toAdminPartner,
  toBookingEvent,
  toBookingUser,
  toOwnerPartner,
  toPublicPartner,
  toPublicUser,
  toSelfUser,
} from '../src/shared/utils/bookingPrivacy.js';

const FORBIDDEN = [
  'password_hash',
  'otp_hash',
  'bank_account_no',
  'bank_ifsc',
  'temp_bank_account_no',
  'temp_bank_ifsc',
  'pan_number',
  'aadhaar_number',
  'gst_number',
];

const hostileUser = {
  user_id: 'u1',
  name: 'Alice',
  email: 'a@x.com',
  phone_number: '999',
  password_hash: 'HASH',
  otp_hash: 'OTPHASH',
  fcm_token: 'tok',
  avatar_url: 'av',
  city: 'C',
  state: 'S',
  wallet_balance: 10,
};

const hostilePartner = {
  partner_id: 'p1',
  email: 'p@x.com',
  phone_number: '888',
  password_hash: 'HASH',
  bank_account_no: '123456',
  bank_ifsc: 'IFSC0001',
  temp_bank_account_no: '999',
  temp_bank_ifsc: 'IFSC9999',
  pan_number: 'PAN123',
  aadhaar_number: 'AADHAR123',
  gst_number: 'GST123',
  fcm_token: 'tok',
  avatar_url: 'av',
  kyc_status: 'pending',
};

const hostileBooking = {
  booking_id: 'b1',
  user_id: 'u1',
  venue_id: 'v1',
  slot_id: 's1',
  status: 'CONFIRMED',
  payment_mode: 'online',
  eticket_code: 'APV-SECRET',
  online_amount: 500,
  venue_amount: 0,
  created_at: '2026-01-01',
  user: hostileUser,
  venue: { venue_id: 'v1', name: 'Arena', partner: hostilePartner },
  slot: { slot_id: 's1' },
};

function assertNoForbidden(obj: any, path = 'root') {
  if (!obj || typeof obj !== 'object') return;
  if (Array.isArray(obj)) {
    obj.forEach((v, i) => assertNoForbidden(v, `${path}[${i}]`));
    return;
  }
  for (const k of Object.keys(obj)) {
    expect(FORBIDDEN, `${path}.${k} must never be exposed`).not.toContain(k);
    assertNoForbidden(obj[k], `${path}.${k}`);
  }
}

describe('B1: booking WebSocket event privacy', () => {
  it('global event contains only scalar allowlist keys', () => {
    const event = toBookingEvent(hostileBooking);
    expect(Object.keys(event).sort()).toEqual(
      ['booking_id', 'created_at', 'payment_mode', 'slot_id', 'status', 'venue_id'].sort()
    );
    assertNoForbidden(event);
  });

  it('global event never carries eticket, amounts, user, or partner', () => {
    const event = toBookingEvent(hostileBooking);
    expect(event).not.toHaveProperty('eticket_code');
    expect(event).not.toHaveProperty('online_amount');
    expect(event).not.toHaveProperty('user_id');
    expect(event).not.toHaveProperty('user');
    expect(event).not.toHaveProperty('partner');
  });

  it('targeted event may carry owner fields but never credentials/bank', () => {
    const event = toBookingEvent(hostileBooking, { includePrivate: true });
    expect(event.eticket_code).toBe('APV-SECRET');
    expect(event.online_amount).toBe(500);
    assertNoForbidden(event);
  });

  it('all broadcast(bookings) call sites pass Event payloads, never raw bookings', () => {
    const serviceSrc = fs.readFileSync(
      new URL('../src/modules/client/client.service.ts', import.meta.url), 'utf8');
    const adminSrc = fs.readFileSync(
      new URL('../src/modules/admin/admin.service.ts', import.meta.url), 'utf8');
    for (const [name, src] of [['client.service', serviceSrc], ['admin.service', adminSrc]] as const) {
      const lines = src.split('\n').filter((l) => l.includes("broadcast('bookings'"));
      expect(lines.length, `${name} must still emit booking events`).toBeGreaterThan(0);
      for (const line of lines) {
        expect(line, `${name}: ${line.trim()} must emit an Event payload`).toMatch(/Event/);
        expect(line, `${name}: must not broadcast a raw booking object`).not.toMatch(/broadcast\('bookings', booking\)/);
      }
    }
  });
});

describe('B2: API response privacy', () => {
  it('prisma select allowlists contain no forbidden keys', () => {
    for (const sel of [SAFE_USER_PUBLIC_SELECT, SAFE_BOOKING_USER_SELECT, SAFE_PARTNER_PUBLIC_SELECT]) {
      for (const k of Object.keys(sel)) {
        expect(FORBIDDEN).not.toContain(k);
      }
    }
  });

  it('booking counterparty card exposes contact but no secrets', () => {
    const u = toBookingUser(hostileUser);
    expect(u).toMatchObject({ user_id: 'u1', name: 'Alice', email: 'a@x.com', phone_number: '999' });
    assertNoForbidden(u);
  });

  it('public user/partner cards expose no contact beyond profile basics', () => {
    assertNoForbidden(toPublicUser(hostileUser));
    assertNoForbidden(toPublicPartner(hostilePartner));
    expect(toPublicPartner(hostilePartner)).toEqual({ partner_id: 'p1', avatar_url: 'av' });
  });

  it('self/owner/admin views strip credentials but keep needed fields', () => {
    const self = toSelfUser(hostileUser);
    expect(self.name).toBe('Alice');
    assertNoForbidden(self);
    assertNoForbidden(toOwnerPartner(hostilePartner));
    const admin = toAdminPartner(hostilePartner);
    expect(admin.kyc_status).toBe('pending'); // admin still sees verification state
    assertNoForbidden(admin);
  });

  it('deep booking sanitizer cleans nested user/venue.partner graphs', () => {
    const clean: any = sanitizeBookingForResponse(hostileBooking);
    expect(clean.user.name).toBe('Alice');
    expect(clean.user).not.toHaveProperty('password_hash');
    expect(clean.venue.partner).toEqual({ partner_id: 'p1', avatar_url: 'av' });
    expect(clean.online_amount).toBe(500); // business fields preserved
    assertNoForbidden(clean);
  });

  it('password_hash appears in src only on credential write/verify lines', () => {
    const files = [
      '../src/modules/client/client.service.ts',
      '../src/modules/admin/admin.service.ts',
      '../src/modules/client/client.controller.ts',
    ];
    for (const f of files) {
      const src = fs.readFileSync(new URL(f, import.meta.url), 'utf8');
      const hits = src.split('\n').filter((l) => l.includes('password_hash'));
      for (const line of hits) {
        const t = line.trim();
        // Allowed: bcrypt write/verify, null-out on delete, truthiness guard
        // before bcrypt.compare, and the transient updateData assignment.
        // Anything selecting/returning/broadcasting the hash fails.
        const ok =
          /bcrypt\.(hash|compare)/.test(t) ||
          /password_hash:\s*null/.test(t) ||
          /updateData\.password_hash\s*=/.test(t) ||
          /^if\s*\(.*password_hash/.test(t);
        expect(ok, `${f}: unexpected password_hash usage: ${t}`).toBe(true);
        expect(t).not.toMatch(/select|include|broadcast|emitTo|return\s+.*password_hash/);
      }
    }
  });
});

describe('B3: webhook state machine (pure, no credentials needed)', () => {
  it('1. PENDING + correct amount/currency -> CONFIRMED', () => {
    const r = resolveWebhookTransition('PENDING', true, true, 'pending');
    expect(r).toMatchObject({ action: 'confirm', confirmBooking: true, runSideEffects: true });
  });

  it('2. PENDING + wrong amount -> NOT CONFIRMED, mismatch recorded', () => {
    const r = resolveWebhookTransition('PENDING', false, true, 'pending');
    expect(r).toMatchObject({ action: 'record_mismatch', confirmBooking: false, runSideEffects: false });
  });

  it('2b. PENDING + wrong currency -> NOT CONFIRMED', () => {
    const r = resolveWebhookTransition('PENDING', true, false, 'pending');
    expect(r).toMatchObject({ action: 'record_mismatch', confirmBooking: false });
  });

  it('3. CANCELLED + correct capture -> remains CANCELLED (truthful record only)', () => {
    const r = resolveWebhookTransition('CANCELLED', true, true, 'pending');
    expect(r).toMatchObject({ action: 'record_truthful', confirmBooking: false, runSideEffects: false });
  });

  it('4. CONFIRMED + duplicate webhook -> idempotent, no side effects', () => {
    const r = resolveWebhookTransition('CONFIRMED', true, true, 'success');
    expect(r).toMatchObject({ action: 'duplicate', confirmBooking: false, runSideEffects: false });
    const r2 = resolveWebhookTransition('CONFIRMED', true, true, 'pending');
    expect(r2).toMatchObject({ action: 'converge', confirmBooking: false, runSideEffects: false });
  });

  it('5. COMPLETED + capture -> does not regress state', () => {
    const r = resolveWebhookTransition('COMPLETED', true, true, 'pending');
    expect(r.confirmBooking).toBe(false);
    expect(r.runSideEffects).toBe(false);
    expect(r.action).toBe('record_truthful');
  });

  it('6. success txn short-circuits everything (duplicate)', () => {
    for (const status of ['PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED', undefined]) {
      const r = resolveWebhookTransition(status, true, true, 'success');
      expect(r.action).toBe('duplicate');
    }
  });
});
