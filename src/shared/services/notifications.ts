import { getMessaging } from 'firebase-admin/messaging';
import { getFcmApp } from '../../config/fcm.js';
import { prisma } from '../../config/prisma.js';
import { redis } from '../../config/redis.js';
import { logger } from '../../config/logger.js';

export interface PushResult {
  sent: boolean;
  invalidToken: boolean;
  persisted: boolean;
}

/**
 * P2-9 consistent notification strategy:
 * - Every user/partner notification is persisted to user_notifications
 *   (inbox survives push failure).
 * - Push is best-effort; invalid/unknown registration tokens are cleared
 *   from the profile so we stop sending to dead tokens.
 * - Optional Redis-backed dedupe keys prevent duplicate notifications for
 *   the same event (e.g. verify + webhook both confirming).
 * - Payloads carry titles/bodies only — never secrets, hashes, or KYC data.
 */

const DEDUPE_TTL_SECONDS = 86400;

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

async function persistNotification(
  recipientId: string,
  recipientType: 'user' | 'partner',
  category: string,
  title: string,
  body: string
): Promise<boolean> {
  try {
    await prisma.userNotification.create({
      data: { recipient_id: recipientId, recipient_type: recipientType, category, title, body },
    });
    return true;
  } catch (err) {
    logger.error('Failed to persist notification:', err);
    return false;
  }
}

async function claimDedupe(dedupeKey: string | undefined): Promise<boolean> {
  if (!dedupeKey) return true;
  const claimed = await redis.set(`notif:dedupe:${dedupeKey}`, '1', { NX: true, EX: DEDUPE_TTL_SECONDS });
  return claimed !== null;
}

export async function notifyUser(
  userId: string,
  category: string,
  title: string,
  body: string,
  dedupeKey?: string
): Promise<PushResult> {
  const proceed = await claimDedupe(dedupeKey).catch(() => true);
  const persisted = await persistNotification(userId, 'user', category, title, body);
  if (!proceed) return { sent: false, invalidToken: false, persisted };
  const user = await prisma.user.findUnique({ where: { user_id: userId }, select: { fcm_token: true } });
  if (!user?.fcm_token) return { sent: false, invalidToken: false, persisted };
  const { sent, invalidToken } = await sendToToken(user.fcm_token, title, body);
  if (invalidToken) {
    await prisma.user.update({ where: { user_id: userId }, data: { fcm_token: null } }).catch(() => undefined);
  }
  return { sent, invalidToken, persisted };
}

export async function notifyPartner(
  partnerId: string,
  category: string,
  title: string,
  body: string,
  dedupeKey?: string
): Promise<PushResult> {
  const proceed = await claimDedupe(dedupeKey).catch(() => true);
  const persisted = await persistNotification(partnerId, 'partner', category, title, body);
  if (!proceed) return { sent: false, invalidToken: false, persisted };
  const partner = await prisma.partner.findUnique({ where: { partner_id: partnerId }, select: { fcm_token: true } });
  if (!partner?.fcm_token) return { sent: false, invalidToken: false, persisted };
  const { sent, invalidToken } = await sendToToken(partner.fcm_token, title, body);
  if (invalidToken) {
    await prisma.partner.update({ where: { partner_id: partnerId }, data: { fcm_token: null } }).catch(() => undefined);
  }
  return { sent, invalidToken, persisted };
}

/** Test helper: pure classification of FCM error codes. */
export function isInvalidFcmTokenErrorCode(code: string | undefined | null): boolean {
  return isInvalidTokenError({ code });
}
