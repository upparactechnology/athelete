import { getMessaging } from 'firebase-admin/messaging';
import { getFcmApp } from '../../config/fcm.js';
import { prisma } from '../../config/prisma.js';
import { logger } from '../../config/logger.js';

export interface PushResult {
  sent: boolean;
  invalidToken: boolean;
  persisted: boolean;
  /** True when another request already recorded this event. */
  duplicate?: boolean;
}

/**
 * P2-9 consistent notification strategy (DB-first dedupe):
 *
 *   DB insert succeeds  -> this request owns the notification -> send push
 *   DB reports duplicate -> do NOT send another push
 *   DB unavailable       -> report persistence failure (never claim duplicate)
 *
 * The (recipient_id, dedupe_key) unique constraint is the source of truth;
 * Redis is intentionally NOT in the decision path (a Redis win + DB loss
 * previously suppressed the only push). Without a dedupe key every call
 * persists (legacy behavior preserved).
 *
 * Inbox persistence and FCM delivery are separate: a push failure never
 * deletes the inbox row; an invalid token is still cleared from the profile.
 * Payloads carry titles/bodies only — never secrets, hashes, or KYC data.
 */

export interface NotifyDeps {
  db?: any;
  getToken?: (kind: 'user' | 'partner', id: string) => Promise<string | null>;
  clearToken?: (kind: 'user' | 'partner', id: string) => Promise<void>;
  send?: (token: string, title: string, body: string) => Promise<{ sent: boolean; invalidToken: boolean }>;
}

function defaultDeps(): Required<NotifyDeps> {
  return {
    db: prisma,
    getToken: async (kind, id) => {
      if (kind === 'user') {
        const u = await prisma.user.findUnique({ where: { user_id: id }, select: { fcm_token: true } });
        return u?.fcm_token ?? null;
      }
      const p = await prisma.partner.findUnique({ where: { partner_id: id }, select: { fcm_token: true } });
      return p?.fcm_token ?? null;
    },
    clearToken: async (kind, id) => {
      if (kind === 'user') {
        await prisma.user.update({ where: { user_id: id }, data: { fcm_token: null } }).catch(() => undefined);
      } else {
        await prisma.partner.update({ where: { partner_id: id }, data: { fcm_token: null } }).catch(() => undefined);
      }
    },
    send: sendToToken,
  };
}

function isInvalidTokenError(err: any): boolean {
  const code = err?.code || err?.errorInfo?.code || '';
  return (
    code === 'messaging/invalid-registration-token' ||
    code === 'messaging/registration-token-not-registered' ||
    code === 'messaging/invalid-argument'
  );
}

async function sendToToken(token: string, title: string, body: string): Promise<{ sent: boolean; invalidToken: boolean }> {
  try {
    const app = await getFcmApp();
    if (!app) return { sent: false, invalidToken: false };
    await getMessaging(app).send({ token, notification: { title, body } });
    return { sent: true, invalidToken: false };
  } catch (err: any) {
    if (isInvalidTokenError(err)) {
      logger.warn(`FCM token invalid, will clear from profile: ${err?.code}`);
      return { sent: false, invalidToken: true };
    }
    logger.error('FCM send failed (will retry on next event):', err?.message || err);
    return { sent: false, invalidToken: false };
  }
}

/**
 * Durable inbox write. With a dedupeKey, exactly one row per
 * (recipient, key) exists: concurrent writers converge via the unique
 * constraint and losers are reported as duplicates (no second push).
 * Without a key, every call persists (legacy behavior preserved).
 * A DB outage returns persisted:false/duplicate:false (never a false
 * duplicate); the push path still attempts delivery independently.
 */
async function persistNotification(
  db: any,
  recipientId: string,
  recipientType: 'user' | 'partner',
  category: string,
  title: string,
  body: string,
  dedupeKey?: string
): Promise<{ persisted: boolean; duplicate: boolean }> {
  if (!dedupeKey) {
    try {
      await db.userNotification.create({
        data: { recipient_id: recipientId, recipient_type: recipientType, category, title, body },
      });
      return { persisted: true, duplicate: false };
    } catch (err) {
      logger.error('Failed to persist notification:', err);
      return { persisted: false, duplicate: false };
    }
  }
  try {
    await db.userNotification.create({
      data: {
        recipient_id: recipientId, recipient_type: recipientType, category, title, body,
        dedupe_key: dedupeKey,
      },
    });
    return { persisted: true, duplicate: false };
  } catch (err: any) {
    if (err?.code === 'P2002') {
      return { persisted: true, duplicate: true };
    }
    logger.error('Failed to persist notification:', err);
    return { persisted: false, duplicate: false };
  }
}

async function deliverToRecipient(
  deps: Required<NotifyDeps>,
  kind: 'user' | 'partner',
  id: string,
  category: string,
  title: string,
  body: string,
  dedupeKey?: string
): Promise<PushResult> {
  // DB FIRST: only the writer of the inbox row may push.
  let wrote = { persisted: false, duplicate: false };
  try {
    wrote = await persistNotification(deps.db, id, kind, category, title, body, dedupeKey);
  } catch {
    wrote = { persisted: false, duplicate: false };
  }
  if (wrote.duplicate) return { sent: false, invalidToken: false, persisted: true, duplicate: true };
  let token: string | null = null;
  try {
    token = await deps.getToken(kind, id);
  } catch (err) {
    logger.error('FCM token lookup failed:', err);
  }
  if (!token) return { sent: false, invalidToken: false, persisted: wrote.persisted };
  let sent = false;
  let invalidToken = false;
  try {
    ({ sent, invalidToken } = await deps.send(token, title, body));
  } catch (err) {
    logger.error('FCM send threw (inbox row kept):', err);
  }
  if (invalidToken) {
    await deps.clearToken(kind, id).catch(() => undefined);
  }
  return { sent, invalidToken, persisted: wrote.persisted };
}

export async function notifyUser(
  userId: string,
  category: string,
  title: string,
  body: string,
  dedupeKey?: string,
  deps?: NotifyDeps
): Promise<PushResult> {
  const d = { ...defaultDeps(), ...(deps || {}) };
  return deliverToRecipient(d, 'user', userId, category, title, body, dedupeKey);
}

export async function notifyPartner(
  partnerId: string,
  category: string,
  title: string,
  body: string,
  dedupeKey?: string,
  deps?: NotifyDeps
): Promise<PushResult> {
  const d = { ...defaultDeps(), ...(deps || {}) };
  return deliverToRecipient(d, 'partner', partnerId, category, title, body, dedupeKey);
}

/** Test helper: pure classification of FCM error codes. */
export function isInvalidFcmTokenErrorCode(code: string | undefined | null): boolean {
  return isInvalidTokenError({ code });
}
