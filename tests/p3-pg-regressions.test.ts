/**
 * P3 real-PostgreSQL regression guards (UNIT, no database).
 *
 * Phase 3 disposable-DB runs proved three defects that fakes cannot catch:
 *  1. `uuid = text` (42883): Prisma binds JS strings as text; the coupon
 *     FOR UPDATE lock compared uuid to text and failed 100% on real PG.
 *  2. void deserialize (P2010): pg_advisory_xact_lock returns void, which
 *     Prisma $queryRaw cannot deserialize on real PG.
 *  3. Partial unique indexes are inexpressible in Prisma schema, so
 *     `db push` environments silently lose the single-pending-refund guard.
 */
import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import { claimRefundIntent } from '../src/shared/services/refunds.js';

const couponsSrc = fs.readFileSync(new URL('../src/shared/services/coupons.ts', import.meta.url), 'utf8');
const refundsSrc = fs.readFileSync(new URL('../src/shared/services/refunds.ts', import.meta.url), 'utf8');

describe('P3-1 coupon row locks are uuid-cast (real-PG 42883)', () => {
  it('every FOR UPDATE on coupons casts the bound id to ::uuid', () => {
    const locks = couponsSrc.match(/SELECT coupon_id FROM coupons WHERE coupon_id = \$\{[^}]+\}[^`]*FOR UPDATE/g) || [];
    expect(locks.length).toBe(2);
    for (const l of locks) expect(l).toContain('::uuid');
  });

  it('no bare uuid=text comparison remains on the coupon lock path', () => {
    expect(couponsSrc).not.toMatch(/coupon_id = \$\{[^}]+}\s+FOR UPDATE/);
  });
});

describe('P3-2 advisory lock avoids void deserialize (real-PG P2010)', () => {
  it('pg_advisory_xact_lock goes through $executeRaw, never $queryRaw', () => {
    expect(refundsSrc).toContain('$executeRaw`SELECT pg_advisory_xact_lock');
    expect(refundsSrc).not.toContain('$queryRaw`SELECT pg_advisory_xact_lock');
  });

  it('claimRefundIntent works with an executeRaw-only tx (no $queryRaw dep)', async () => {
    const ops: string[] = [];
    const tx: any = {
      async $executeRaw() {
        ops.push('lock');
        return 1;
      },
      transaction: {
        async findMany({ where }: any) {
          ops.push(`read:${where.txn_status}`);
          return [];
        },
        async create({ data }: any) {
          ops.push('create');
          return { ...data, txn_id: 'intent1', created_at: new Date() };
        },
      },
    };
    const out = await claimRefundIntent(tx, {
      req: { bookingId: 'b1' },
      booking: { booking_id: 'b1', online_amount: 1000, convenience_fee: 0 },
      capture: { razorpay_order_id: 'order_1' },
      paymentId: 'pay_mock_1',
      mockPayment: true,
      quote: { amount: 950, eligibility: 'FULL_REFUND' },
      now: new Date(),
    });
    expect(out.intent.txn_id).toBe('intent1');
    expect(out.amount).toBe(950);
    expect(ops).toContain('lock');
    expect(ops).toContain('create');
  });
});

describe('P3-3 single-pending-refund guard survives db push', () => {
  it('guard migration exists and carries the partial unique index', () => {
    const guard = fs.readFileSync(
      new URL('../prisma/migrations/20260929_refund_partial_index_guard/migration.sql', import.meta.url),
      'utf8'
    );
    expect(guard).toContain('transactions_one_pending_refund_per_booking');
    expect(guard).toContain("WHERE \"txn_type\" = 'refund' AND \"txn_status\" = 'pending'");
    expect(guard).toContain('IF NOT EXISTS');
  });

  it('phase2 migration still owns the canonical definition (parity)', () => {
    const phase2 = fs.readFileSync(
      new URL('../prisma/migrations/20260928_phase2_hardening/migration.sql', import.meta.url),
      'utf8'
    );
    expect(phase2).toContain('transactions_one_pending_refund_per_booking');
  });
});
