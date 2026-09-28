import { describe, expect, it } from 'vitest';

import { resolveFailedPaymentTransition } from '../src/shared/utils/bookingPrivacy.js';
import { releaseBookingOnFailedPayment } from '../src/shared/services/paymentFailure.js';

/* -------------------------------------------------------------------------
 * Minimal Prisma-compatible fake: findUnique / findMany / updateMany with
 * equality + `{ not }` + array `in` where-matching, plus a passthrough
 * $transaction. State lives in plain arrays so tests can assert on the
 * exact final rows (booking / transaction / slot).
 * ---------------------------------------------------------------------- */

function matchWhere(row: any, where: any): boolean {
  for (const [key, cond] of Object.entries(where ?? {})) {
    if (cond !== null && typeof cond === 'object' && !Array.isArray(cond) && 'not' in (cond as any)) {
      if (row[key] === (cond as any).not) return false;
    } else if (Array.isArray(cond)) {
      if (!cond.includes(row[key])) return false;
    } else if (cond !== null && typeof cond === 'object') {
      // Unsupported operator object: treat as match (never over-restrict).
      continue;
    } else if (row[key] !== cond) {
      return false;
    }
  }
  return true;
}

function collection(rows: any[]) {
  return {
    rows,
    async findUnique({ where }: any) {
      const found = rows.find((r) => matchWhere(r, where));
      return found ? { ...found } : null;
    },
    async findMany({ where }: any) {
      return rows.filter((r) => matchWhere(r, where ?? {})).map((r) => ({ ...r }));
    },
    async updateMany({ where, data }: any) {
      let count = 0;
      for (const row of rows) {
        if (matchWhere(row, where)) {
          Object.assign(row, data);
          count += 1;
        }
      }
      return { count };
    },
  };
}

function makeDb(seed: { booking: any; slot: any; txn: any }) {
  const booking = collection([seed.booking]);
  const slot = collection([seed.slot]);
  const txn = collection([seed.txn]);
  const db: any = { booking, slot, transaction: txn, couponRedemption: { findMany: async () => [] } };
  db.$transaction = async (fn: any) => fn(db);
  return db;
}

const BID = 'bbbbbbbb-1111-1111-1111-111111111111';
const TID = 'tttttttt-1111-1111-1111-111111111111';
const SID = 'ssssssss-1111-1111-1111-111111111111';

function seedBooking(status: string, extra: any = {}) {
  return {
    booking_id: BID,
    user_id: 'user-1',
    venue_id: 'venue-1',
    slot_id: SID,
    status,
    expires_at: new Date(Date.now() + 30 * 60 * 1000),
    venue: { venue_id: 'venue-1', partner_id: 'partner-1' },
    ...extra,
  };
}

function seedSlot(status = 'booked') {
  return { slot_id: SID, venue_id: 'venue-1', status };
}

function seedTxn(txnStatus = 'pending') {
  return { txn_id: TID, booking_id: BID, razorpay_order_id: 'order_1', txn_status: txnStatus };
}

describe('payment.failed webhook state machine (pure)', () => {
  it('PENDING booking + unsettled txn -> release booking and slot', () => {
    const r = resolveFailedPaymentTransition('PENDING', 'pending');
    expect(r).toMatchObject({ action: 'release', releaseBooking: true, releaseSlot: true });
  });

  it('never releases CONFIRMED / CANCELLED / EXPIRED / COMPLETED bookings', () => {
    for (const status of ['CONFIRMED', 'CANCELLED', 'EXPIRED', 'COMPLETED', undefined]) {
      const r = resolveFailedPaymentTransition(status as any, 'pending');
      expect(r.action).toBe('no_op');
      expect(r.releaseBooking).toBe(false);
      expect(r.releaseSlot).toBe(false);
      expect(r.reason).toContain('booking-not-pending');
    }
  });

  it('a settled success transaction always wins over a failed event', () => {
    const r = resolveFailedPaymentTransition('PENDING', 'success');
    expect(r).toMatchObject({ action: 'no_op', releaseBooking: false, reason: 'transaction-already-success' });
  });
});

describe('releaseBookingOnFailedPayment (fake DB, end-state assertions)', () => {
  it('A. failed payment: PENDING -> CANCELLED, slot -> available, txn -> failed', async () => {
    const db = makeDb({ booking: seedBooking('PENDING'), slot: seedSlot('booked'), txn: seedTxn('pending') });

    const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

    expect(out).toMatchObject({ released: true, slotReleased: true, bookingStatus: 'CANCELLED' });
    expect(db.booking.rows[0].status).toBe('CANCELLED');
    expect(db.booking.rows[0].expires_at).toBeNull();
    expect(db.slot.rows[0].status).toBe('available');
    expect(db.transaction.rows[0].txn_status).toBe('failed');
    expect(db.transaction.rows[0].razorpay_payment_id).toBe('pay_failed_1');
  });

  it('B. idempotent: a second delivery performs no further transitions', async () => {
    const db = makeDb({ booking: seedBooking('PENDING'), slot: seedSlot('booked'), txn: seedTxn('pending') });

    const first = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);
    const second = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

    expect(first.released).toBe(true);
    expect(second).toMatchObject({ released: false, slotReleased: false, bookingStatus: 'CANCELLED' });
    expect(second.reason).toBe('booking-not-pending:CANCELLED');
    expect(db.booking.rows[0].status).toBe('CANCELLED');
    expect(db.slot.rows[0].status).toBe('available');
    expect(db.transaction.rows[0].txn_status).toBe('failed');
  });

  it('C. CONFIRMED booking is never modified; slot stays booked', async () => {
    const db = makeDb({ booking: seedBooking('CONFIRMED'), slot: seedSlot('booked'), txn: seedTxn('pending') });

    const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

    expect(out).toMatchObject({ released: false, slotReleased: false, bookingStatus: 'CONFIRMED' });
    expect(db.booking.rows[0].status).toBe('CONFIRMED');
    expect(db.slot.rows[0].status).toBe('booked');
    // The failed attempt is still recorded truthfully on the ledger.
    expect(db.transaction.rows[0].txn_status).toBe('failed');
  });

  it('D. settled success transaction is never downgraded, PENDING booking never released', async () => {
    const db = makeDb({ booking: seedBooking('PENDING'), slot: seedSlot('booked'), txn: seedTxn('success') });

    const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_late', db);

    expect(out).toMatchObject({ released: false, reason: 'transaction-already-success' });
    expect(db.booking.rows[0].status).toBe('PENDING');
    expect(db.slot.rows[0].status).toBe('booked');
    expect(db.transaction.rows[0].txn_status).toBe('success');
    expect(db.transaction.rows[0].razorpay_payment_id).toBeUndefined();
  });

  it.each(['CANCELLED', 'EXPIRED', 'COMPLETED'])(
    'E. %s booking is left untouched (no slot churn, no status change)',
    async (status) => {
      const db = makeDb({ booking: seedBooking(status), slot: seedSlot('available'), txn: seedTxn('pending') });

      const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

      expect(out.released).toBe(false);
      expect(db.booking.rows[0].status).toBe(status);
      expect(db.slot.rows[0].status).toBe('available');
      expect(db.transaction.rows[0].txn_status).toBe('failed');
    }
  );

  it('F. release race: a concurrent confirm wins, the booking is never cancelled', async () => {
    const db = makeDb({ booking: seedBooking('PENDING'), slot: seedSlot('booked'), txn: seedTxn('pending') });
    // Between the read and the conditional flip another writer confirms.
    const originalUpdateMany = db.booking.updateMany;
    db.booking.updateMany = async (args: any) => {
      db.booking.rows[0].status = 'CONFIRMED';
      return originalUpdateMany(args);
    };

    const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

    expect(out).toMatchObject({ released: false, reason: 'release-race-lost', bookingStatus: 'CONFIRMED' });
    expect(db.booking.rows[0].status).toBe('CONFIRMED');
    expect(db.slot.rows[0].status).toBe('booked');
  });

  it('G. slot already released: no double release, no clobbering', async () => {
    const db = makeDb({ booking: seedBooking('PENDING'), slot: seedSlot('available'), txn: seedTxn('pending') });

    const out = await releaseBookingOnFailedPayment(BID, TID, 'pay_failed_1', db);

    expect(out).toMatchObject({ released: true, slotReleased: false });
    expect(db.booking.rows[0].status).toBe('CANCELLED');
    expect(db.slot.rows[0].status).toBe('available');
  });
});
