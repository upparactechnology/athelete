import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { UnauthorizedError, ValidationError } from './errors.js';
import type { UserRole } from '../types/index.js';

/** Injectable DB handle (defaults to Prisma). Tests pass an in-memory fake. */
export type SessionDb = typeof prisma;

const ACCESS_TTL = '1d';
const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/** Grace window where a just-rotated token may be retried (concurrent refresh). */
const ROTATION_GRACE_MS = 120_000;

interface RefreshClaims {
  sub: string;
  role: UserRole;
  status: string;
  jti: string;
  fid: string;
}

async function accountActive(db: SessionDb, userId: string, role: string): Promise<void> {
  if (role === 'user') {
    const user = await db.user.findUnique({ where: { user_id: userId } });
    if (!user) throw new UnauthorizedError('Account no longer exists. Please log in again.');
    if (user.status !== 'Active') throw new UnauthorizedError('This account is no longer active.');
  } else if (role === 'partner') {
    const partner = await db.partner.findUnique({ where: { partner_id: userId } });
    if (!partner) throw new UnauthorizedError('Account no longer exists. Please log in again.');
    if ((partner as any).kyc_status === 'deleted') throw new UnauthorizedError('This account is no longer active.');
  } else if (role === 'admin') {
    // Admin identity is environment-bound (no admin table); the session row
    // uses the zero UUID for the Uuid column (legacy convention).
    if (userId !== 'admin-id-default' && userId !== '00000000-0000-0000-0000-000000000000') {
      throw new UnauthorizedError('Invalid admin session.');
    }
  } else {
    throw new UnauthorizedError('Invalid session role.');
  }
}

/**
 * P2-7 session issuance. Access JWT stays {sub, role, status}; the refresh
 * JWT additionally carries jti (this token) + fid (login family). Only the
 * bcrypt hash is stored — database rows are never returned to clients.
 */
export async function createSession(
  userId: string,
  role: UserRole,
  familyId?: string,
  db: SessionDb = prisma
): Promise<{ accessToken: string; refreshToken: string }> {
  const jti = randomUUID();
  const fid = familyId ?? randomUUID();
  const accessToken = jwt.sign({ sub: userId, role, status: 'Active' }, env.JWT_ACCESS_SECRET, {
    expiresIn: ACCESS_TTL,
  });
  const refreshToken = jwt.sign(
    { sub: userId, role, status: 'Active', jti, fid } as RefreshClaims,
    env.JWT_REFRESH_SECRET,
    { expiresIn: '7d' }
  );
  await db.refreshToken.create({
    data: {
      user_id: userId,
      role,
      token_hash: await bcrypt.hash(refreshToken, 10),
      jti,
      family_id: fid,
      expires_at: new Date(Date.now() + REFRESH_TTL_MS),
    },
  });
  return { accessToken, refreshToken };
}

/** P2-7 logout: revoke the presented refresh session (idempotent). */
export async function revokeSession(refreshToken: string, db: SessionDb = prisma): Promise<{ revoked: boolean }> {
  if (!refreshToken || typeof refreshToken !== 'string') return { revoked: false };
  const decoded = jwt.decode(refreshToken) as (RefreshClaims & { exp?: number }) | null;
  if (!decoded?.jti) return { revoked: false };
  const row = await db.refreshToken.findUnique({ where: { jti: decoded.jti } });
  if (!row || row.revoked_at) return { revoked: false };
  await db.refreshToken.update({ where: { jti: decoded.jti }, data: { revoked_at: new Date() } });
  return { revoked: true };
}

/** Revoke every refresh session for an identity (reuse response, deletion). */
export async function revokeAllSessions(userId: string, db: SessionDb = prisma): Promise<number> {
  const res = await db.refreshToken.updateMany({
    where: { user_id: userId, revoked_at: null },
    data: { revoked_at: new Date() },
  });
  return res.count;
}

/**
 * P2-7 rotation with an ATOMIC database claim.
 *
 * Security invariant: ONE refresh token -> AT MOST ONE successful rotation.
 * The presented token is claimed with a single conditional update:
 *
 *   UPDATE refresh_tokens SET revoked_at = NOW()
 *   WHERE jti = ? AND revoked_at IS NULL AND expires_at > NOW()
 *
 * Only the request whose update affects exactly 1 row may issue the
 * successor session. A concurrent loser sees count 0 and never mints.
 *
 * Grace policy (documented): a request presenting an already-rotated token
 * WITHIN 120s of its rotation is treated as a concurrent-retry, not theft:
 * it atomically claims the family's current live head and receives a
 * successor, converging the family to a single live tip. Reuse outside the
 * grace window (or of an expired/foreign token) revokes the whole family.
 */
export async function refreshSession(refreshToken: string, db: SessionDb = prisma): Promise<{ accessToken: string; refreshToken: string }> {
  if (!refreshToken || typeof refreshToken !== 'string') {
    throw new ValidationError('Refresh token is required');
  }
  let claims: RefreshClaims;
  try {
    claims = jwt.verify(refreshToken, env.JWT_REFRESH_SECRET) as RefreshClaims;
  } catch {
    throw new UnauthorizedError('Invalid or expired refresh token');
  }
  if (!claims?.sub || !claims?.jti || !claims?.fid || !claims?.role) {
    throw new UnauthorizedError('Invalid refresh token');
  }

  const row = await db.refreshToken.findUnique({ where: { jti: claims.jti } });
  const hashMatches = row ? await bcrypt.compare(refreshToken, row.token_hash) : false;

  if (!row || !hashMatches) {
    // Unknown token presenting a valid signature: possible forgery/replay —
    // kill the family to contain it. Revocation failure is logged loudly:
    // the request still fails closed below.
    await revokeAllSessions(claims.sub, db).catch((err) =>
      logger.error('Family revocation failed after unrecognized refresh token:', err)
    );
    throw new UnauthorizedError('Refresh session not recognized. Please log in again.');
  }

  // ATOMIC CLAIM of the presented token. Exactly one concurrent request wins.
  const now = new Date();
  const claimed = await db.refreshToken.updateMany({
    where: { jti: claims.jti, revoked_at: null, expires_at: { gt: now } },
    data: { revoked_at: now },
  });

  if (claimed.count === 1) {
    // Winner: the token is now dead; issue the successor in the same family.
    // Account check AFTER the claim (fail closed; token already consumed).
    await accountActive(db, claims.sub, row.role);
    return createSession(claims.sub, claims.role as UserRole, claims.fid, db);
  }

  // Loser or replayer: the token was already dead when we tried to claim it.
  const refreshedRow = await db.refreshToken.findUnique({ where: { jti: claims.jti } });
  const revokedAtMs = refreshedRow?.revoked_at ? new Date(refreshedRow.revoked_at).getTime() : 0;
  const inGrace = refreshedRow?.revoked_at != null && Date.now() - revokedAtMs <= ROTATION_GRACE_MS;

  if (inGrace) {
    // Concurrent-retry grace: atomically claim the family's live head, then
    // issue from it. The winner of the original claim may not have finished
    // inserting the successor yet, so retry briefly before concluding theft.
    // Converges the family to a single live tip.
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const head = await db.refreshToken.findFirst({
        where: { family_id: claims.fid, revoked_at: null, expires_at: { gt: new Date() } },
        orderBy: { expires_at: 'desc' },
      });
      if (head) {
        const headClaimed = await db.refreshToken.updateMany({
          where: { token_id: head.token_id, revoked_at: null, expires_at: { gt: new Date() } },
          data: { revoked_at: new Date() },
        });
        if (headClaimed.count === 1) {
          await accountActive(db, claims.sub, head.role);
          return createSession(claims.sub, claims.role as UserRole, claims.fid, db);
        }
      }
      if (attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    }
  }

  // Genuine reuse outside grace (or expired token): assume theft, kill family.
  // Revocation failure is logged loudly; the request still fails closed.
  await revokeAllSessions(claims.sub, db).catch((err) =>
    logger.error('Family revocation failed after refresh reuse:', err)
  );
  throw new UnauthorizedError('Refresh session was already used. Please log in again.');
}
