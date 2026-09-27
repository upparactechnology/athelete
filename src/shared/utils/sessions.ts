import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { UnauthorizedError, ValidationError } from './errors.js';
import type { UserRole } from '../types/index.js';

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

async function accountActive(userId: string, role: string): Promise<void> {
  if (role === 'user') {
    const user = await prisma.user.findUnique({ where: { user_id: userId } });
    if (!user) throw new UnauthorizedError('Account no longer exists. Please log in again.');
    if (user.status !== 'Active') throw new UnauthorizedError('This account is no longer active.');
  } else if (role === 'partner') {
    const partner = await prisma.partner.findUnique({ where: { partner_id: userId } });
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
  familyId?: string
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
  await prisma.refreshToken.create({
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
export async function revokeSession(refreshToken: string): Promise<{ revoked: boolean }> {
  if (!refreshToken || typeof refreshToken !== 'string') return { revoked: false };
  const decoded = jwt.decode(refreshToken) as (RefreshClaims & { exp?: number }) | null;
  if (!decoded?.jti) return { revoked: false };
  const row = await prisma.refreshToken.findUnique({ where: { jti: decoded.jti } });
  if (!row || row.revoked_at) return { revoked: false };
  await prisma.refreshToken.update({ where: { jti: decoded.jti }, data: { revoked_at: new Date() } });
  return { revoked: true };
}

/** Revoke every refresh session for an identity (reuse response, deletion). */
export async function revokeAllSessions(userId: string): Promise<number> {
  const res = await prisma.refreshToken.updateMany({
    where: { user_id: userId, revoked_at: null },
    data: { revoked_at: new Date() },
  });
  return res.count;
}

/**
 * P2-7 rotation. Returns a fresh pair; the presented token is invalidated.
 * Reuse of a rotated token revokes the whole family (theft response), except
 * within a short grace window where concurrent refresh retries converge on
 * the family's live head instead of locking the user out.
 */
export async function refreshSession(refreshToken: string): Promise<{ accessToken: string; refreshToken: string }> {
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

  const row = await prisma.refreshToken.findUnique({ where: { jti: claims.jti } });
  const hashMatches = row ? await bcrypt.compare(refreshToken, row.token_hash) : false;

  if (!row || !hashMatches) {
    // Unknown token presenting a valid signature: possible forgery/replay —
    // kill the family to contain it.
    await revokeAllSessions(claims.sub).catch(() => undefined);
    throw new UnauthorizedError('Refresh session not recognized. Please log in again.');
  }
  if (row.revoked_at || row.expires_at <= new Date()) {
    const revokedAt = row.revoked_at ? new Date(row.revoked_at).getTime() : 0;
    const inGrace = row.revoked_at != null && Date.now() - revokedAt <= ROTATION_GRACE_MS;
    if (inGrace) {
      // Concurrent refresh retry: rotate from the family's live head.
      const head = await prisma.refreshToken.findFirst({
        where: { family_id: claims.fid, revoked_at: null, expires_at: { gt: new Date() } },
        orderBy: { expires_at: 'desc' },
      });
      if (head) {
        await prisma.refreshToken.update({
          where: { token_id: head.token_id },
          data: { revoked_at: new Date() },
        });
        return createSession(claims.sub, claims.role as UserRole, claims.fid);
      }
    }
    // Reuse of a dead token outside grace: assume theft, revoke family.
    await revokeAllSessions(claims.sub).catch(() => undefined);
    throw new UnauthorizedError('Refresh session was already used. Please log in again.');
  }

  await accountActive(claims.sub, row.role);

  // Rotate: invalidate presented token, issue successor in the same family.
  await prisma.refreshToken.update({
    where: { token_id: row.token_id },
    data: { revoked_at: new Date() },
  });
  return createSession(claims.sub, claims.role as UserRole, claims.fid);
}
