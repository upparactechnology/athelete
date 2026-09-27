import { prisma } from '../../config/prisma.js';
import { ConflictError, ValidationError } from '../utils/errors.js';

export interface CouponClaimInput {
  couponId: string;
  userId: string;
  now?: Date;
}

/**
 * P2-4 atomic coupon claim (call INSIDE the booking transaction).
 *
 *Concurrency safety is database-held, never application-held:
 * 1. SELECT ... FOR UPDATE locks the coupon row, serializing concurrent
 *    claims on the SAME coupon (different coupons proceed in parallel).
 * 2. Fresh re-read + validity check (a pre-check outside the tx is stale).
 * 3. Per-user applied-count check AFTER the lock -> no two bookings can
 *    both observe priorUses = 0 for per_user_limit = 1.
 * 4. Conditional used_count increment (second guard for the global limit).
 *
 * A failed booking transaction rolls everything back automatically.
 */
export async function claimCouponUsage(tx: any, input: CouponClaimInput): Promise<{ coupon: any }> {
  const now = input.now ?? new Date();
  // $queryRaw parameterizes (never interpolate request input into SQL).
  await tx.$queryRaw`SELECT coupon_id FROM coupons WHERE coupon_id = ${input.couponId} FOR UPDATE`;
  const coupon = await tx.coupon.findUnique({ where: { coupon_id: input.couponId } });
  if (!coupon || !coupon.is_active) {
    throw new ValidationError('Coupon is not active');
  }
  if (new Date(coupon.valid_from) > now || new Date(coupon.valid_until) < now) {
    throw new ValidationError('Coupon is expired or not yet valid');
  }
  const priorUses = await tx.couponRedemption.count({
    where: { coupon_id: input.couponId, user_id: input.userId, status: 'applied' },
  });
  if (priorUses >= (coupon.per_user_limit ?? 1)) {
    throw new ConflictError('Coupon per-user limit reached', 'COUPON_USER_LIMIT');
  }
  const claimed = await tx.coupon.updateMany({
    where: {
      coupon_id: input.couponId,
      is_active: true,
      valid_from: { lte: now },
      valid_until: { gte: now },
      used_count: { lt: coupon.usage_limit },
    },
    data: { used_count: { increment: 1 } },
  });
  if (claimed.count === 0) {
    throw new ConflictError('Coupon usage limit reached', 'COUPON_EXHAUSTED');
  }
  return { coupon };
}

/**
 * P2-4/P2-7 coupon rollback: APPLIED -> ROLLED_BACK exactly once per
 * redemption, with exactly one used_count decrement.
 *
 * Two concurrent cancellations share one outcome via a conditional flip:
 * only the request whose updateMany matches (red_id + status applied)
 * performs the decrement. Repeat calls are safe no-ops.
 */
export async function rollbackCouponForBooking(bookingId: string, db: any = prisma): Promise<{ rolledBack: boolean }> {
  if (!bookingId) return { rolledBack: false };
  const applied = await db.couponRedemption.findMany({
    where: { booking_id: bookingId, status: 'applied' },
    select: { red_id: true, coupon_id: true },
  });
  let rolledBack = false;
  for (const row of applied) {
    const flipped = await db.couponRedemption.updateMany({
      where: { red_id: row.red_id, status: 'applied' },
      data: { status: 'rolled_back' },
    });
    if (flipped.count === 0) continue; // another cancellation won this row
    rolledBack = true;
    await db.coupon.updateMany({
      where: { coupon_id: row.coupon_id },
      data: { used_count: { decrement: 1 } },
    });
    // Clamp drift: usage can never go negative.
    await db.coupon.updateMany({
      where: { coupon_id: row.coupon_id, used_count: { lt: 0 } },
      data: { used_count: 0 },
    });
  }
  return { rolledBack };
}
