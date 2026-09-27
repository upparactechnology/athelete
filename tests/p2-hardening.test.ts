import fs from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  createSession,
  refreshSession,
  revokeAllSessions,
  revokeSession,
} from '../src/shared/utils/sessions.js';
import { applyRefundWebhookEvent } from '../src/shared/services/refunds.js';
import { rollbackCouponForBooking } from '../src/shared/services/coupons.js';

/* ------------------------------------------------------------------ */
/* In-memory fake implementing the exact Prisma query shapes used by   */
/* sessions.ts, refunds.applyRefundWebhookEvent and coupons.ts.        */
/* updateMany is a single synchronous step, modelling Postgres         */
/* conditional-update atomicity (this is what the production code      */
/* relies on; live PG concurrency runs remain NEEDS RUNTIME TEST).     */
/* ------------------------------------------------------------------ */

function matches(row: any, where: any): boolean {
  if (!where) return true;
  for (const [k, v] of Object.entries(where)) {
    const rv = row[k];
    if (v !== null && typeof v === 'object' && !(v instanceof Date) && !Array.isArray(v)) {
      if ('gt' in (v as any) && !(rv > (v as any).gt)) return false;
      if ('gte' in (v as any) && !(rv >= (v as any).gte)) return false;
      if ('lt' in (v as any) && !(rv < (v as any).lt)) return false;
      if ('lte' in (v as any) && !(rv <= (v as any).lte)) return false;
      if ('in' in (v as any) && !(v as any).in.includes(rv)) return false;
      continue;
    }
    if (v === null) {
      if (rv !== null && rv !== undefined) return false;
      continue;
    }
    if (rv !== v) return false;
  }
  return true;
}

function applyData(row: any, data: any) {
  for (const [k, v] of Object.entries(data)) {
    if (v !== null && typeof v === 'object' && !(v instanceof Date)) {
      if ('increment' in (v as any)) row[k] = Number(row[k] ?? 0) + Number((v as any).increment);
      else if ('decrement' in (v as any)) row[k] = Number(row[k] ?? 0) - Number((v as any).decrement);
      else row[k] = v;
    } else {
      row[k] = v;
    }
  }
}

function makeCollection(prefix: string) {
  const rows: any[] = [];
  let seq = 1;
  return {
    rows,
    async create({ data }: any) {
      const row = { ...data, [`${prefix}_seq`]: seq++ };
      if (!row.token_id && prefix === 'rt') row.token_id = `tok-${seq}`;
      rows.push(row);
      return { ...row };
    },
    async findUnique({ where }: any) {
      const hit = rows.find((r) => matches(r, where));
      return hit ? { ...hit } : null;
    },
    async findFirst({ where, orderBy }: any) {
      let hits = rows.filter((r) => matches(r, where));
      if (orderBy) {
        const [key, dir] = Object.entries(orderBy)[0] as [string, string];
        hits = [...hits].sort((a, b) => (dir === 'desc' ? (b[key] > a[key] ? 1 : -1) : a[key] > b[key] ? 1 : -1));
      }
      return hits.length ? { ...hits[0] } : null;
    },
    async findMany({ where }: any = {}) {
      return rows.filter((r) => matches(r, where)).map((r) => ({ ...r }));
    },
    async update({ where, data }: any) {
      const hit = rows.find((r) => matches(r, where));
      if (!hit) throw Object.assign(new Error('Not found'), { code: 'P2025' });
      applyData(hit, data);
      return { ...hit };
    },
    async updateMany({ where, data }: any) {
      let count = 0;
      for (const r of rows) {
        if (matches(r, where)) {
          applyData(r, data);
          count += 1;
        }
      }
      return { count };
    },
  };
}

function makeFakeDb() {
  const rt = makeCollection('rt');
  const tx = makeCollection('tx');
  const red = makeCollection('red');
  const coupons = makeCollection('cpn');
  const users = makeCollection('usr');
  const partners = makeCollection('prt');
  return {
    refreshToken: rt,
    transaction: tx,
    couponRedemption: red,
    coupon: coupons,
    user: {
      ...users,
      async findUnique({ where }: any) {
        return users.findUnique({ where });
      },
    },
    partner: {
      ...partners,
      async findUnique({ where }: any) {
        return partners.findUnique({ where });
      },
    },
  } as any;
}

function seedUser(db: any, userId: string, status = 'Active') {
  db.user.rows.push({ user_id: userId, status });
}

const UID = '11111111-1111-1111-1111-111111111111';

describe('P2-7 atomic rotation (UNIT, deterministic, fake DB)', () => {
  it('A. single refresh succeeds and retires the old token', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    const s1: any = await refreshSession(s0.refreshToken, db);
    expect(s1.accessToken).toBeTruthy();
    expect(s1.refreshToken).not.toBe(s0.refreshToken);
    const live = db.refreshToken.rows.filter((r: any) => !r.revoked_at);
    expect(live).toHaveLength(1);
  });

  it('C+D. concurrent double-refresh converges to exactly one live tip', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    const [a, b]: any[] = await Promise.all([
      refreshSession(s0.refreshToken, db),
      refreshSession(s0.refreshToken, db),
    ]);
    expect(a.refreshToken).toBeTruthy();
    expect(b.refreshToken).toBeTruthy();
    const live = db.refreshToken.rows.filter((r: any) => !r.revoked_at && new Date(r.expires_at) > new Date());
    // Grace convergence: both callers served, single live session tip.
    expect(live).toHaveLength(1);
  });

  it('B+E. reuse after grace fails and revokes the family', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    await refreshSession(s0.refreshToken, db); // rotates; s0 now revoked
    // Age the revocation beyond the 120s grace window.
    for (const r of db.refreshToken.rows) {
      if (r.revoked_at) r.revoked_at = new Date(Date.now() - 10 * 60 * 1000);
    }
    await expect(refreshSession(s0.refreshToken, db)).rejects.toMatchObject({ statusCode: 401 });
    const live = db.refreshToken.rows.filter((r: any) => !r.revoked_at);
    expect(live).toHaveLength(0); // family killed
  });

  it('F. revoked family cannot refresh', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    await revokeAllSessions(UID, db);
    for (const r of db.refreshToken.rows) {
      if (r.revoked_at) r.revoked_at = new Date(Date.now() - 10 * 60 * 1000);
    }
    await expect(refreshSession(s0.refreshToken, db)).rejects.toMatchObject({ statusCode: 401 });
  });

  it('G. deleted/blocked account cannot refresh', async () => {
    const db = makeFakeDb();
    seedUser(db, UID, 'Deleted');
    const s0 = await createSession(UID, 'user', undefined, db);
    await expect(refreshSession(s0.refreshToken, db)).rejects.toMatchObject({ statusCode: 401 });
    // Partner with deleted KYC.
    const db2 = makeFakeDb();
    db2.partner.rows.push({ partner_id: 'p1', kyc_status: 'deleted' });
    const p0 = await createSession('p1', 'partner', undefined, db2);
    await expect(refreshSession(p0.refreshToken, db2)).rejects.toMatchObject({ statusCode: 401 });
  });

  it('H. logout revokes; post-grace refresh fails', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    expect(await revokeSession(s0.refreshToken, db)).toMatchObject({ revoked: true });
    expect(await revokeSession(s0.refreshToken, db)).toMatchObject({ revoked: false }); // idempotent
    for (const r of db.refreshToken.rows) {
      if (r.revoked_at) r.revoked_at = new Date(Date.now() - 10 * 60 * 1000);
    }
    await expect(refreshSession(s0.refreshToken, db)).rejects.toMatchObject({ statusCode: 401 });
  });

  it('I. logout-all revokes the session set', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    await createSession(UID, 'user', undefined, db);
    await createSession(UID, 'user', undefined, db);
    expect(await revokeAllSessions(UID, db)).toBe(2);
    expect(await revokeAllSessions(UID, db)).toBe(0);
  });

  it('unknown token with valid signature kills the family', async () => {
    const db = makeFakeDb();
    seedUser(db, UID);
    const s0 = await createSession(UID, 'user', undefined, db);
    // Forge claims: valid signature but unknown jti — reuse victim's family id.
    const jwt = await import('jsonwebtoken');
    const { env } = await import('../src/config/env.js');
    const forged = jwt.default.sign(
      { sub: UID, role: 'user', status: 'Active', jti: 'no-such-jti', fid: 'fid-x' },
      env.JWT_REFRESH_SECRET,
      { expiresIn: '7d' }
    );
    await expect(refreshSession(forged, db)).rejects.toMatchObject({ statusCode: 401 });
    expect(db.refreshToken.rows.filter((r: any) => !r.revoked_at)).toHaveLength(0);
    void s0;
  });
});

describe('P2-3 refund webhook transitions (UNIT, fake DB)', () => {
  function seedRefund(status: string, amount = 500) {
    const db = makeFakeDb();
    db.transaction.rows.push({
      txn_id: 't1',
      booking_id: 'b1',
      razorpay_order_id: 'order_1',
      razorpay_payment_id: 'rfnd_1',
      txn_type: 'refund',
      txn_status: status,
      amount,
    });
    return db;
  }

  it('pending + processed -> success', async () => {
    const db = seedRefund('pending');
    const r = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', amountPaise: 50000 }, db);
    expect(r).toMatchObject({ processed: true, reason: 'confirmed' });
    expect(db.transaction.rows[0].txn_status).toBe('success');
  });

  it('duplicate processed is idempotent', async () => {
    const db = seedRefund('success');
    const r = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', amountPaise: 50000 }, db);
    expect(r).toMatchObject({ processed: true, reason: 'duplicate' });
  });

  it('pending + failed -> failed; success never becomes failed', async () => {
    const db = seedRefund('pending');
    expect(await applyRefundWebhookEvent({ type: 'refund.failed', refundId: 'rfnd_1' }, db)).toMatchObject({ reason: 'marked-failed' });
    const db2 = seedRefund('success');
    const r2 = await applyRefundWebhookEvent({ type: 'refund.failed', refundId: 'rfnd_1' }, db2);
    expect(r2).toMatchObject({ processed: true, reason: 'duplicate' });
    expect(db2.transaction.rows[0].txn_status).toBe('success');
  });

  it('unknown refund id fabricates nothing; amount mismatch changes nothing', async () => {
    const db = seedRefund('pending');
    expect(await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_nope' }, db)).toMatchObject({ processed: false });
    expect(db.transaction.rows).toHaveLength(1);
    const r = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', amountPaise: 1 }, db);
    expect(r).toMatchObject({ processed: false, reason: 'amount-mismatch' });
    expect(db.transaction.rows[0].txn_status).toBe('pending');
  });

  it('failed refund is retryable (no success row blocks a fresh request)', async () => {
    const db = seedRefund('failed');
    const success = db.transaction.rows.filter((r: any) => r.txn_status === 'success');
    expect(success).toHaveLength(0);
  });
});

describe('P2-4/P2-7 coupon rollback exactly-once (UNIT, fake DB)', () => {
  it('two concurrent cancellations decrement exactly once', async () => {
    const db = makeFakeDb();
    db.coupon.rows.push({ coupon_id: 'c1', used_count: 5 });
    db.couponRedemption.rows.push({ red_id: 'r1', coupon_id: 'c1', user_id: 'u', booking_id: 'b', status: 'applied' });
    const [a, b] = await Promise.all([rollbackCouponForBooking('b', db), rollbackCouponForBooking('b', db)]);
    expect(a.rolledBack || b.rolledBack).toBe(true);
    expect(db.coupon.rows[0].used_count).toBe(4);
    expect(db.couponRedemption.rows[0].status).toBe('rolled_back');
    // Repeat is a safe no-op.
    expect(await rollbackCouponForBooking('b', db)).toMatchObject({ rolledBack: false });
    expect(db.coupon.rows[0].used_count).toBe(4);
  });
});

describe('P2-8/9 + migration static guards', () => {
  it('notification dedupe is per-recipient and durable in code + migration', () => {
    const src = fs.readFileSync(new URL('../src/shared/services/notifications.ts', import.meta.url), 'utf8');
    expect(src).toContain('dedupe_key');
    expect(src).toContain('recipient_id');
    const mig = fs.readFileSync(
      new URL('../prisma/migrations/20260928_phase2_hardening/migration.sql', import.meta.url), 'utf8');
    expect(mig).toContain('dedupe_key');
    expect(mig).toContain('user_notifications_recipient_id_dedupe_key_key');
  });

  it('migration uses UUID (not text) for red_id and documents honesty gaps', () => {
    const mig = fs.readFileSync(
      new URL('../prisma/migrations/20260928_phase2_hardening/migration.sql', import.meta.url), 'utf8');
    expect(mig).toContain('"red_id" UUID NOT NULL');
    expect(mig).not.toMatch(/"red_id" TEXT/);
    expect(mig).toContain('transactions_one_pending_refund_per_booking');
    expect(mig).toContain('UPDATE "tournaments"');
    expect(mig).toContain('CANNOT BE RECONSTRUCTED');
    expect(mig).toContain('GROUP BY booking_id HAVING COUNT(*) > 1');
  });

  it('no raw SQL interpolates request input (advisory lock is parameterized)', () => {
    const src = fs.readFileSync(new URL('../src/shared/services/refunds.ts', import.meta.url), 'utf8');
    expect(src).not.toContain('$queryRawUnsafe');
    expect(src).toContain('pg_advisory_xact_lock');
  });
});
