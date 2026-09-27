import { prisma } from '../../config/prisma.js';
import { redis } from '../../config/redis.js';
import { logger } from '../../config/logger.js';
import { WebSocketService } from './websocket.js';
import { toBookingEvent } from '../utils/bookingPrivacy.js';

const EXPIRY_LOCK_KEY = 'job:booking-expiry-lock';
const EXPIRY_LOCK_TTL_SECONDS = 300;

export interface ExpiryRunResult {
  scanned: number;
  expired: number;
  ranAt: string;
}

type Db = typeof prisma;

/**
 * P2-1 pending-booking expiry sweeper.
 *
 * Idempotent: the PENDING->EXPIRED flip is a conditional updateMany, so
 * running twice (or concurrently on two instances that both pass the Redis
 * advisory lock) expires each booking at most once. Slot release only fires
 * for the winner of the conditional flip.
 *
 * Safety: never touches CONFIRMED/CANCELLED/COMPLETED rows; never releases a
 * slot unless this run performed the expiry flip.
 */
export async function expirePendingBookings(
  db: Db = prisma,
  opts: { now?: Date; batchSize?: number; lockTtlSeconds?: number } = {}
): Promise<ExpiryRunResult> {
  const now = opts.now ?? new Date();
  const batchSize = opts.batchSize ?? 100;
  const ranAt = now.toISOString();

  // Advisory distributed lock (safe under PM2 cluster / multiple dynos).
  let lock: string | null = null;
  try {
    lock = await redis.set(EXPIRY_LOCK_KEY, ranAt, { NX: true, EX: opts.lockTtlSeconds ?? EXPIRY_LOCK_TTL_SECONDS });
  } catch {
    lock = 'unavailable-redis-bypass';
  }
  if (lock === null) {
    return { scanned: 0, expired: 0, ranAt };
  }

  try {
    const due = await db.booking.findMany({
      where: { status: 'PENDING', expires_at: { lte: now } },
      take: batchSize,
      select: { booking_id: true, slot_id: true, venue_id: true },
    });

    let expired = 0;
    for (const row of due) {
      const flipped = await db.booking.updateMany({
        where: { booking_id: row.booking_id, status: 'PENDING' },
        data: { status: 'EXPIRED', expires_at: null },
      });
      if (flipped.count === 0) continue; // confirmed/cancelled concurrently — leave alone
      expired += 1;
      // Release the held slot only for rows THIS run expired.
      await db.slot.updateMany({
        where: { slot_id: row.slot_id, status: 'booked' },
        data: { status: 'available' },
      });
      try {
        WebSocketService.broadcast(
          'bookings',
          toBookingEvent({ booking_id: row.booking_id, venue_id: row.venue_id, slot_id: row.slot_id, status: 'EXPIRED' })
        );
      } catch {
        // notifications must never break expiry
      }
    }
    return { scanned: due.length, expired, ranAt };
  } finally {
    if (lock !== 'unavailable-redis-bypass') {
      await redis.del(EXPIRY_LOCK_KEY).catch(() => undefined);
    }
  }
}

/**
 * Interval driver. Started once from index.ts (see startExpiryJob).
 * Interval-based, no new infrastructure; safe with multiple instances
 * thanks to the advisory Redis lock.
 */
export function startExpiryJob(opts: { intervalMs: number; batchSize: number }): NodeJS.Timeout {
  logger.info(`Booking expiry job scheduled every ${opts.intervalMs}ms (batch ${opts.batchSize}).`);
  const timer = setInterval(() => {
    expirePendingBookings(prisma, { batchSize: opts.batchSize }).catch((err) =>
      logger.error('Booking expiry sweep failed:', err)
    );
  }, opts.intervalMs);
  // Don't hold the event loop open in tests/scripts.
  (timer as any).unref?.();
  return timer;
}
