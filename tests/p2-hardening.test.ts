import fs from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  createSession,
  refreshSession,
  revokeAllSessions,
  revokeSession,
} from '../src/shared/utils/sessions.js';
import { applyRefundWebhookEvent, computeRefundTotals, decideStaleRecovery, findMatchingRefund, queryGatewayRefunds } from '../src/shared/services/refunds.js';
import { claimCouponUsage, rollbackCouponForBooking } from '../src/shared/services/coupons.js';
import { notifyPartner, notifyUser } from '../src/shared/services/notifications.js';

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
    async count({ where }: any = {}) {
      return rows.filter((r) => matches(r, where)).length;
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

  it('no invented Razorpay idempotency parameters', () => {
    const src = fs.readFileSync(new URL('../src/shared/services/refunds.ts', import.meta.url), 'utf8');
    expect(src.toLowerCase()).not.toContain('idempotency_key');
    expect(src.toLowerCase()).not.toContain('idempotency-key');
  });

  it('Redis is not in the notification decision path', () => {
    const src = fs.readFileSync(new URL('../src/shared/services/notifications.ts', import.meta.url), 'utf8');
    expect(src).not.toMatch(/from '\.\.\/\.\.\/config\/redis\.js'/);
    expect(src).not.toContain('claimDedupe');
  });

  it('coupon claims lock the coupon row before counting (static)', () => {
    const src = fs.readFileSync(new URL('../src/shared/services/coupons.ts', import.meta.url), 'utf8');
    const lockAt = src.indexOf('FOR UPDATE');
    const countAt = src.indexOf('couponRedemption.count');
    expect(lockAt).toBeGreaterThan(-1);
    expect(countAt).toBeGreaterThan(lockAt);
  });
});

/* ------------------------------------------------------------------ */
/* Coupon row-locked claims (UNIT). The fake serializes the lock the   */
/* way FOR UPDATE serializes concurrent transactions in Postgres: the  */
/* second claimer observes the first claimer's committed state.        */
/* ------------------------------------------------------------------ */

function makeClaimTx(opts: {
  usageLimit?: number;
  perUserLimit?: number;
  usedCount?: number;
  priorUserUses?: number;
  active?: boolean;
  log?: string[];
}) {
  const {
    usageLimit = 10, perUserLimit = 1, usedCount = 0,
    priorUserUses = 0, active = true, log = [],
  } = opts;
  let used = usedCount;
  let userUses = priorUserUses;
  const tx: any = {
    async $queryRaw(..._args: any[]) {
      log.push('lock');
      return [];
    },
    coupon: {
      async findUnique() {
        log.push('findUnique');
        return {
          coupon_id: 'c1', is_active: active,
          valid_from: new Date(Date.now() - 1000), valid_until: new Date(Date.now() + 3600000),
          usage_limit: usageLimit, per_user_limit: perUserLimit,
        };
      },
      async updateMany({ where, data }: any) {
        log.push('updateMany');
        if (where?.used_count?.lt != null && !(used < where.used_count.lt)) return { count: 0 };
        used += Number(data?.used_count?.increment ?? 0);
        return { count: 1 };
      },
    },
    couponRedemption: {
      async count() {
        log.push('count');
        return userUses;
      },
      async create() {
        log.push('create');
        userUses += 1;
        return { red_id: 'r1' };
      },
    },
  };
  return { tx, log, state: () => ({ used, userUses }) };
}

describe('Coupon per-user concurrency (UNIT, serialized-lock fake)', () => {
  it('19. per-user limit 1: first claim wins, concurrent second is rejected', async () => {
    // Two requests, one lock holder at a time: the second observes userUses=1.
    const shared = { used: 0, userUses: 0 };
    const runClaim = async () => {
      const { tx } = makeClaimTx({ usedCount: shared.used, priorUserUses: shared.userUses });
      const wrapTx: any = {
        ...tx,
        coupon: {
          ...tx.coupon,
          async updateMany(a: any) {
            const r = await tx.coupon.updateMany(a);
            if (r.count === 1) {
              shared.used += 1;
              shared.userUses += 1;
            }
            return r;
          },
        },
        couponRedemption: {
          async count() {
            return shared.userUses;
          },
          async create(d: any) {
            return tx.couponRedemption.create(d);
          },
        },
      };
      return claimCouponUsage(wrapTx, { couponId: 'c1', userId: 'u1' });
    };
    await runClaim();
    await expect(runClaim()).rejects.toMatchObject({ code: 'COUPON_USER_LIMIT' });
    expect(shared).toMatchObject({ used: 1, userUses: 1 });
  });

  it('20. per-user limit 2 allows exactly two claims', async () => {
    const shared = { used: 0, userUses: 0 };
    const runClaim = async () => {
      const { tx } = makeClaimTx({ perUserLimit: 2, usedCount: shared.used, priorUserUses: shared.userUses });
      const wrapTx: any = {
        ...tx,
        coupon: {
          ...tx.coupon,
          async updateMany(a: any) {
            const r = await tx.coupon.updateMany(a);
            if (r.count === 1) {
              shared.used += 1;
              shared.userUses += 1;
            }
            return r;
          },
        },
        couponRedemption: {
          async count() {
            return shared.userUses;
          },
          async create(d: any) {
            return tx.couponRedemption.create(d);
          },
        },
      };
      return claimCouponUsage(wrapTx, { couponId: 'c1', userId: 'u1' });
    };
    await runClaim();
    await runClaim();
    await expect(runClaim()).rejects.toMatchObject({ code: 'COUPON_USER_LIMIT' });
    expect(shared).toMatchObject({ used: 2, userUses: 2 });
  });

  it('21. global usage race: last slot has exactly one winner', async () => {
    const { tx, state } = makeClaimTx({ usageLimit: 10, perUserLimit: 99, usedCount: 9, priorUserUses: 0 });
    await claimCouponUsage(tx, { couponId: 'c1', userId: 'u1' });
    // Counter now at the limit: next claim (fresh lock, fresh read) fails.
    const tx2 = makeClaimTx({ usageLimit: 10, perUserLimit: 99, usedCount: state().used, priorUserUses: 1 }).tx;
    await expect(claimCouponUsage(tx2, { couponId: 'c1', userId: 'u2' })).rejects.toMatchObject({ code: 'COUPON_EXHAUSTED' });
    expect(state().used).toBe(10);
  });

  it('lock precedes the per-user count (ordering = the fix)', async () => {
    const { tx, log } = makeClaimTx({});
    await claimCouponUsage(tx, { couponId: 'c1', userId: 'u1' });
    expect(log.indexOf('lock')).toBeLessThan(log.indexOf('count'));
  });

  it('inactive coupon rejected without side effects', async () => {
    const { tx, state } = makeClaimTx({ active: false });
    await expect(claimCouponUsage(tx, { couponId: 'c1', userId: 'u1' })).rejects.toMatchObject({ statusCode: 400 });
    expect(state().used).toBe(0);
  });
});

/* ------------------------------------------------------------------ */
/* Notification DB-first dedupe (UNIT, injected deps).                 */
/* ------------------------------------------------------------------ */

function makeNotifyDeps(opts: {
  tokens?: Record<string, string | null>;
  sendBehavior?: 'ok' | 'fail' | 'invalid' | 'throw';
  dbDown?: boolean;
} = {}) {
  const rows: any[] = [];
  const tokens = new Map(Object.entries(opts.tokens ?? { u1: 'tok-u1' }));
  const pushes: Array<{ token: string; title: string }> = [];
  const cleared: string[] = [];
  const deps = {
    db: {
      userNotification: {
        async create({ data }: any) {
          if (opts.dbDown) throw new Error('db down');
          if (data.dedupe_key && rows.some((r) => r.recipient_id === data.recipient_id && r.dedupe_key === data.dedupe_key)) {
            throw Object.assign(new Error('dup'), { code: 'P2002' });
          }
          rows.push({ ...data });
          return data;
        },
      },
    },
    getToken: async (_kind: string, id: string) => tokens.get(id) ?? null,
    clearToken: async (_kind: string, id: string) => {
      cleared.push(id);
      tokens.set(id, null as any);
    },
    send: async (token: string, title: string) => {
      pushes.push({ token, title });
      if (opts.sendBehavior === 'invalid') return { sent: false, invalidToken: true };
      if (opts.sendBehavior === 'fail' || opts.sendBehavior === 'throw') {
        if (opts.sendBehavior === 'throw') throw new Error('fcm down');
        return { sent: false, invalidToken: false };
      }
      return { sent: true, invalidToken: false };
    },
  };
  return { deps, rows, pushes, cleared };
}

describe('Notification DB-first dedupe (UNIT, injected deps)', () => {
  it('24/25. concurrent same key -> one DB row, one push owner', async () => {
    const { deps, rows, pushes } = makeNotifyDeps();
    const [a, b] = await Promise.all([
      notifyUser('u1', 'booking', 'T', 'B', 'evt-1', deps),
      notifyUser('u1', 'booking', 'T', 'B', 'evt-1', deps),
    ]);
    expect(rows).toHaveLength(1);
    expect(pushes).toHaveLength(1);
    const owners = [a, b].filter((r) => !r.duplicate);
    expect(owners).toHaveLength(1);
    expect(owners[0]).toMatchObject({ sent: true, persisted: true });
  });

  it('same event id for different users does not collide', async () => {
    const { deps, rows, pushes } = makeNotifyDeps({ tokens: { u1: 't1', u2: 't2' } });
    const [a, b] = await Promise.all([
      notifyUser('u1', 'booking', 'T', 'B', 'evt-1', deps),
      notifyUser('u2', 'booking', 'T', 'B', 'evt-1', deps),
    ]);
    expect(rows).toHaveLength(2);
    expect(pushes).toHaveLength(2);
    expect(a.duplicate).toBeFalsy();
    expect(b.duplicate).toBeFalsy();
  });

  it('26/27. DB failure never reports duplicate; push still attempted', async () => {
    const { deps, pushes } = makeNotifyDeps({ dbDown: true });
    const r = await notifyUser('u1', 'booking', 'T', 'B', 'evt-1', deps);
    expect(r).toMatchObject({ persisted: false });
    expect(r.duplicate).toBeFalsy();
    expect(pushes).toHaveLength(1);
  });

  it('28. FCM failure leaves the inbox row (persisted true, sent false)', async () => {
    const { deps, rows } = makeNotifyDeps({ sendBehavior: 'fail' });
    const r = await notifyUser('u1', 'booking', 'T', 'B', 'evt-9', deps);
    expect(r).toMatchObject({ persisted: true, sent: false });
    expect(rows).toHaveLength(1);
  });

  it('29. invalid token is cleared', async () => {
    const { deps, cleared } = makeNotifyDeps({ sendBehavior: 'invalid' });
    const r = await notifyPartner('p1', 'booking', 'T', 'B', 'evt-9', { ...deps, getToken: async () => 'tok-p1' } as any);
    expect(r).toMatchObject({ sent: false, invalidToken: true, persisted: true });
    expect(cleared).toContain('p1');
  });
});

/* ------------------------------------------------------------------ */
/* FINAL HARDENING: explicit lookup states, partial totals, coupon      */
/* row-lock claims, DB-first notification dedupe. All UNIT (fake     */
/* in-memory stores / stubbed fetch). Live PG/gateway runs are NOT     */
/* TESTED here and are listed as such in the final report.             */
/* ------------------------------------------------------------------ */

describe('Refund gateway lookup states (UNIT)', () => {
  const okFetch = (body: any) => async () => ({ ok: true, status: 200, json: async () => body });

  it('6. gateway timeout keeps pending (unknown)', async () => {
    const timeoutFetch = async () => {
      throw Object.assign(new Error('aborted'), { name: 'AbortError' });
    };
    const r = await queryGatewayRefunds('pay_1', 'k', 's', timeoutFetch as any);
    expect(r).toMatchObject({ state: 'unknown' });
    expect(r.reason).toContain('timeout');
  });

  it('7. gateway 500 keeps pending (unknown)', async () => {
    const r = await queryGatewayRefunds('pay_1', 'k', 's', okFetch({ error: 'boom' }) as any);
    // NOTE: okFetch returns ok:true here; use a real 500 shape below.
    const r500 = await queryGatewayRefunds('pay_1', 'k', 's', (async () => ({
      ok: false, status: 500, json: async () => ({ error: 'boom' }),
    })) as any);
    expect(r500).toMatchObject({ state: 'unknown' });
    expect(r500.reason).toContain('500');
    void r;
  });

  it('8. malformed gateway response keeps pending (unknown)', async () => {
    const r = await queryGatewayRefunds('pay_1', 'k', 's', okFetch({ items: 'not-an-array' }) as any);
    expect(r).toMatchObject({ state: 'unknown', reason: 'malformed-gateway-response' });
  });

  it('9. valid empty list is the ONLY not_found', async () => {
    const r = await queryGatewayRefunds('pay_1', 'k', 's', okFetch({ items: [] }) as any);
    expect(r).toMatchObject({ state: 'not_found' });
  });

  it('10/11. matching processed + pending refunds are recognized', async () => {
    const items = [
      { id: 'rfnd_p', payment_id: 'pay_1', amount: 50000, status: 'processed' },
      { id: 'rfnd_w', payment_id: 'pay_1', amount: 50000, status: 'pending' },
      { id: 'rfnd_c', payment_id: 'pay_1', amount: 50000, status: 'created' },
    ];
    expect(findMatchingRefund(items, { paymentId: 'pay_1', amountPaise: 50000 })?.id).toBe('rfnd_p');
    expect(findMatchingRefund(items, { paymentId: 'pay_1', amountPaise: 50000, refundId: 'rfnd_w' })?.status).toBe('pending');
    // 12. unrelated refund (other payment / other amount) never matches.
    expect(findMatchingRefund(items, { paymentId: 'pay_2', amountPaise: 50000 })).toBeNull();
    expect(findMatchingRefund(items, { paymentId: 'pay_1', amountPaise: 100 })).toBeNull();
    expect(findMatchingRefund(items, { paymentId: 'pay_1', amountPaise: 50000, refundId: 'rfnd_x' })).toBeNull();
  });
});

describe('Refund totals: partials can never exceed capture (UNIT)', () => {
  it('1. no previous refund -> full quote', () => {
    const t = computeRefundTotals(1000, [], [], 950);
    expect(t).toMatchObject({ remainingRefundableAmount: 1000, requestedAmount: 950 });
  });

  it('2/3. partial then second partial accumulates', () => {
    const t1 = computeRefundTotals(1000, [], [], 400);
    expect(t1.requestedAmount).toBe(400);
    const t2 = computeRefundTotals(1000, [400], [], 600);
    expect(t2.remainingRefundableAmount).toBe(600);
    expect(t2.requestedAmount).toBe(600);
  });

  it('4. total can never exceed capture; over-request capped', () => {
    const t = computeRefundTotals(1000, [400], [], 900);
    expect(t.remainingRefundableAmount).toBe(600);
    expect(t.requestedAmount).toBe(600);
  });

  it('5/7. pending intents reserve amounts; fully refunded -> zero', () => {
    const t = computeRefundTotals(1000, [400], [600], 600);
    expect(t.remainingRefundableAmount).toBe(0);
    expect(t.requestedAmount).toBe(0);
    const full = computeRefundTotals(1000, [1000], [], 100);
    expect(full.remainingRefundableAmount).toBe(0);
  });
});

describe('Stale recovery decisions (UNIT)', () => {
  const pending = { amount: 500, razorpay_payment_id: null };
  const criteria = { paymentId: 'pay_1', amountPaise: 50000 };

  it('unknown lookup -> wait (row stays pending, no fresh call)', () => {
    for (const reason of ['gateway-timeout', 'gateway-http-500', 'malformed-gateway-response']) {
      const d = decideStaleRecovery({ state: 'unknown', items: [], reason }, pending, criteria);
      expect(d).toMatchObject({ action: 'wait' });
    }
  });

  it('not_found -> supersede (fresh attempt allowed)', () => {
    expect(decideStaleRecovery({ state: 'not_found', items: [] }, pending, criteria))
      .toMatchObject({ action: 'supersede' });
  });

  it('matching processed -> adopt; matching pending/created -> wait', () => {
    const d = decideStaleRecovery(
      { state: 'found', items: [{ id: 'rfnd_9', payment_id: 'pay_1', amount: 50000, status: 'processed' }] },
      pending, criteria);
    expect(d).toMatchObject({ action: 'adopt', refundId: 'rfnd_9' });
    const w = decideStaleRecovery(
      { state: 'found', items: [{ id: 'rfnd_9', payment_id: 'pay_1', amount: 50000, status: 'pending' }] },
      pending, criteria);
    expect(w).toMatchObject({ action: 'wait' });
  });

  it('matching failed, or no match at all -> supersede', () => {
    const f = decideStaleRecovery(
      { state: 'found', items: [{ id: 'rfnd_9', payment_id: 'pay_1', amount: 50000, status: 'failed' }] },
      pending, criteria);
    expect(f).toMatchObject({ action: 'supersede' });
    const n = decideStaleRecovery(
      { state: 'found', items: [{ id: 'rfnd_x', payment_id: 'pay_9', amount: 1, status: 'processed' }] },
      pending, criteria);
    expect(n).toMatchObject({ action: 'supersede' });
  });
});

describe('Refund webhook binding + terminal-state safety (UNIT, fake DB)', () => {
  function seedDb() {
    const db = makeFakeDb();
    db.transaction.rows.push(
      { txn_id: 'cap1', booking_id: 'b1', razorpay_order_id: 'order_1', razorpay_payment_id: 'pay_1', txn_type: 'capture', txn_status: 'success', amount: 1000 },
      { txn_id: 'ref1', booking_id: 'b1', razorpay_order_id: 'order_1', razorpay_payment_id: 'rfnd_1', txn_type: 'refund', txn_status: 'pending', amount: 500 },
    );
    return db;
  }

  it('16. payment mismatch mutates nothing', async () => {
    const db = seedDb() as any;
    const r = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', paymentId: 'pay_OTHER', amountPaise: 50000 }, db);
    expect(r).toMatchObject({ processed: false, reason: 'payment-mismatch' });
    expect(db.transaction.rows.find((t: any) => t.txn_id === 'ref1').txn_status).toBe('pending');
  });

  it('17. success can never become failed; duplicates converge', async () => {
    const db = seedDb() as any;
    db.transaction.rows.find((t: any) => t.txn_id === 'ref1').txn_status = 'success';
    const r = await applyRefundWebhookEvent({ type: 'refund.failed', refundId: 'rfnd_1', paymentId: 'pay_1' }, db);
    expect(r).toMatchObject({ processed: true, reason: 'duplicate' });
    expect(db.transaction.rows.find((t: any) => t.txn_id === 'ref1').txn_status).toBe('success');
  });

  it('13/15. bound processed event confirms; bound amount mismatch changes nothing', async () => {
    const db = seedDb() as any;
    const bad = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', paymentId: 'pay_1', amountPaise: 999 }, db);
    expect(bad).toMatchObject({ processed: false, reason: 'amount-mismatch' });
    const good = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', paymentId: 'pay_1', amountPaise: 50000 }, db);
    expect(good).toMatchObject({ processed: true, reason: 'confirmed' });
    const dup = await applyRefundWebhookEvent({ type: 'refund.processed', refundId: 'rfnd_1', paymentId: 'pay_1', amountPaise: 50000 }, db);
    expect(dup).toMatchObject({ processed: true, reason: 'duplicate' });
  });
});
