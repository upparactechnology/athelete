import { prisma } from '../../config/prisma.js';

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
