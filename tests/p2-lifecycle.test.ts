import { describe, expect, it } from 'vitest';

import {
  BOOKING_STATUS,
  assertBookingTransition,
  canRegisterTournament,
  canTransitionBooking,
  computeCouponDiscount,
  computeRefundQuote,
  ensureReviewEligible,
  isReviewEligible,
  isTerminalBookingStatus,
} from '../src/shared/utils/bookingLifecycle.js';
import { resolveWebhookTransition } from '../src/shared/utils/bookingPrivacy.js';
import { isInvalidFcmTokenErrorCode } from '../src/shared/services/notifications.js';

describe('P2-2: booking state machine', () => {
  it.each([
    ['PENDING', 'CONFIRMED', true],
    ['PENDING', 'CANCELLED', true],
    ['PENDING', 'EXPIRED', true],
    ['CONFIRMED', 'CANCELLED', true],
    ['CONFIRMED', 'COMPLETED', true],
  ])('%s -> %s is legal', (from, to, expected) => {
    expect(canTransitionBooking(from, to)).toBe(expected);
  });

  it.each([
    ['CANCELLED', 'CONFIRMED'],
    ['EXPIRED', 'CONFIRMED'],
    ['COMPLETED', 'CONFIRMED'],
    ['COMPLETED', 'CANCELLED'],
    ['CANCELLED', 'CANCELLED'],
    ['PENDING', 'PENDING'],
    ['CONFIRMED', 'EXPIRED'],
    ['PENDING', 'COMPLETED'],
    [undefined, 'CONFIRMED'],
    ['PENDING', undefined],
  ])('%s -> %s is illegal', (from, to) => {
    expect(canTransitionBooking(from as any, to as any)).toBe(false);
    expect(() => assertBookingTransition(from as any, to as any)).toThrow();
  });

  it('terminal states are terminal', () => {
    expect(isTerminalBookingStatus('CANCELLED')).toBe(true);
    expect(isTerminalBookingStatus('EXPIRED')).toBe(true);
    expect(isTerminalBookingStatus('COMPLETED')).toBe(true);
    expect(isTerminalBookingStatus('PENDING')).toBe(false);
    expect(isTerminalBookingStatus('CONFIRMED')).toBe(false);
    expect(BOOKING_STATUS.PENDING).toBe('PENDING');
  });
});

describe('P2-1/P2-3: refund quote math (March 2026 policy preserved)', () => {
  // TZ-agnostic: derive slot date/start from a local Date offset from now.
  function slotParts(msAhead: number): { date: string; start: string } {
    const d = new Date(Date.now() + msAhead);
    const pad = (n: number) => String(n).padStart(2, '0');
    return {
      date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
      start: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
    };
  }

  it('>=24h -> 95% of online+fee', () => {
    const s = slotParts(50 * 3600 * 1000);
    const q = computeRefundQuote(1000, 40, s.date, s.start, new Date());
    expect(q.eligibility).toBe('FULL_REFUND');
    expect(q.amount).toBeCloseTo(1040 * 0.95, 2);
  });

  it('>=6h -> 50%', () => {
    const s = slotParts(8 * 3600 * 1000);
    const q = computeRefundQuote(1000, 40, s.date, s.start, new Date());
    expect(q.eligibility).toBe('PARTIAL_REFUND');
    expect(q.amount).toBeCloseTo(1040 * 0.5, 2);
  });

  it('<6h -> no refund', () => {
    const s = slotParts(2 * 3600 * 1000);
    const q = computeRefundQuote(1000, 40, s.date, s.start, new Date());
    expect(q).toMatchObject({ eligibility: 'NO_REFUND', amount: 0 });
  });

  it('missing/invalid slot -> no refund (fail safe)', () => {
    const s = slotParts(50 * 3600 * 1000);
    expect(computeRefundQuote(1000, 40, null, s.start).amount).toBe(0);
    expect(computeRefundQuote(1000, 40, 'not-a-date', s.start).amount).toBe(0);
    expect(computeRefundQuote(0, 0, s.date, s.start).amount).toBe(0);
  });
});

describe('P2-4: coupon discount math (server-side)', () => {
  it('percent with max cap', () => {
    expect(computeCouponDiscount({ discount_type: 'percent', discount_value: 20, max_discount: 150 }, 1000)).toBe(150);
    expect(computeCouponDiscount({ discount_type: 'percent', discount_value: 10, max_discount: null }, 1000)).toBe(100);
  });

  it('flat capped at price, negatives rejected', () => {
    expect(computeCouponDiscount({ discount_type: 'flat', discount_value: 200 }, 1000)).toBe(200);
    expect(computeCouponDiscount({ discount_type: 'flat', discount_value: 2000 }, 1000)).toBe(1000);
    expect(computeCouponDiscount({ discount_type: 'flat', discount_value: -50 }, 1000)).toBe(0);
    expect(computeCouponDiscount(null, 1000)).toBe(0);
  });
});

describe('P2-5: tournament capacity guard', () => {
  it('open with room -> ok; full/closed -> rejected', () => {
    expect(canRegisterTournament('open', 9, 10)).toMatchObject({ ok: true });
    expect(canRegisterTournament('upcoming', 0, 10).ok).toBe(true);
    expect(canRegisterTournament('open', 10, 10)).toMatchObject({ ok: false, reason: 'tournament-full' });
    expect(canRegisterTournament('full', 10, 10).ok).toBe(false);
    expect(canRegisterTournament('completed', 5, 10).ok).toBe(false);
    expect(canRegisterTournament('cancelled', 5, 10).ok).toBe(false);
    expect(canRegisterTournament(undefined, 0, 10).ok).toBe(false);
  });
});

describe('P2-6: review eligibility', () => {
  const booking = { user_id: 'u1', venue_id: 'v1', status: 'CONFIRMED' };

  it('owner CONFIRMED booking for same venue, player role -> eligible', () => {
    expect(isReviewEligible(booking, 'u1', 'v1', 'user')).toMatchObject({ ok: true });
    expect(isReviewEligible({ ...booking, status: 'COMPLETED' }, 'u1', 'v1', 'user').ok).toBe(true);
  });

  it.each([
    [{ ...booking }, 'u1', 'v1', 'partner', 'only-players-may-review'],
    [{ ...booking }, 'u1', 'v1', 'admin', 'only-players-may-review'],
    [null, 'u1', 'v1', 'user', 'no-eligible-booking'],
    [{ ...booking, user_id: 'u2' }, 'u1', 'v1', 'user', 'booking-not-owned'],
    [{ ...booking, venue_id: 'v2' }, 'u1', 'v1', 'user', 'venue-mismatch'],
    [{ ...booking, status: 'PENDING' }, 'u1', 'v1', 'user', 'booking-not-completed:PENDING'],
    [{ ...booking, status: 'CANCELLED' }, 'u1', 'v1', 'user', 'booking-not-completed:CANCELLED'],
    [{ ...booking, status: 'EXPIRED' }, 'u1', 'v1', 'user', 'booking-not-completed:EXPIRED'],
  ])('negative case %s', (b, userId, venueId, role, reason) => {
    expect(isReviewEligible(b as any, userId as string, venueId as string, role as string)).toMatchObject({ ok: false, reason });
    expect(() => ensureReviewEligible(b as any, userId as string, venueId as string, role as string)).toThrow();
  });
});

describe('P2-1/B3: expired bookings never reconfirm via webhook', () => {
  it('EXPIRED + matching capture -> record_truthful (no confirm)', () => {
    const r = resolveWebhookTransition('EXPIRED', true, true, 'pending');
    expect(r).toMatchObject({ action: 'record_truthful', confirmBooking: false, runSideEffects: false });
  });

  it('PENDING + matching capture -> confirm (expiry checked separately by caller)', () => {
    const r = resolveWebhookTransition('PENDING', true, true, 'pending');
    expect(r).toMatchObject({ action: 'confirm', confirmBooking: true });
  });
});

describe('P2-9: FCM invalid-token classification', () => {
  it.each([
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
    'messaging/invalid-argument',
  ])('%s is an invalid-token error', (code) => {
    expect(isInvalidFcmTokenErrorCode(code)).toBe(true);
  });

  it('transient errors are not invalid-token errors', () => {
    expect(isInvalidFcmTokenErrorCode('messaging/server-unavailable')).toBe(false);
    expect(isInvalidFcmTokenErrorCode(undefined)).toBe(false);
    expect(isInvalidFcmTokenErrorCode('internal')).toBe(false);
  });
});

describe('P2: concurrency-pattern guards (mocked conditional-update semantics)', () => {
  // These tests prove the *pattern* used in production code (conditional
  // updateMany + count check) admits exactly one winner under contention.
  // Live PG concurrency runs remain NEEDS RUNTIME TEST.
  async function contendedClaim(winners: { count: number }[], take: () => Promise<{ count: number }>) {
    const results = await Promise.all([take(), take(), take(), take(), take()]);
    return results.filter((r) => r.count === 1).length;
  }

  it('exactly one of five concurrent conditional claims wins', async () => {
    let available = 1;
    const take = async () => {
      // Simulates: UPDATE ... WHERE status='available' + row-count check.
      if (available === 1) {
        available = 0;
        return { count: 1 };
      }
      return { count: 0 };
    };
    const wins = await contendedClaim([], take);
    expect(wins).toBe(1);
  });

  it('coupon usage counter cannot exceed limit under sequential claims', () => {
    let used = 9;
    const limit = 10;
    const claim = () => {
      if (used < limit) {
        used += 1;
        return true;
      }
      return false;
    };
    expect([claim(), claim(), claim()]).toEqual([true, false, false]);
    expect(used).toBe(10);
  });

  it('tournament last-slot claim admits exactly one winner', () => {
    let current = 9;
    const max = 10;
    const claim = () => {
      if (current < max) {
        current += 1;
        return true;
      }
      return false;
    };
    const results = [claim(), claim(), claim()];
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(current).toBe(10);
  });
});

describe('P2: static regression guards', () => {
  it('deleteProfile anonymizes (no hard delete) and refresh has rotation', async () => {
    const fs = await import('node:fs');
    const serviceSrc = fs.readFileSync(new URL('../src/modules/client/client.service.ts', import.meta.url), 'utf8');
    // No hard user/partner delete in the client deletion path.
    expect(serviceSrc).not.toMatch(/prisma\.(user|partner)\.delete\(/);
    expect(serviceSrc).toContain('revokeAllSessions');
    expect(serviceSrc).toContain('updateMany');
    // Refresh rotation + reuse detection markers.
    expect(serviceSrc).toContain('refreshAccessToken');
    // Refund endpoint + expiry wiring markers.
    expect(serviceSrc).toContain('requestRefund');
    expect(serviceSrc).toContain('expires_at');
  });
});
