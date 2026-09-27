-- Phase 2 backend hardening. Additive/nullable only; NOT applied to production.
-- Apply with `prisma migrate deploy` AFTER the pre-migration checks below.
--
-- PRE-MIGRATION DATA CHECKS (run on a production copy first):
-- 1. Duplicate reviews per booking (new unique would fail):
--    SELECT booking_id, COUNT(*) FROM venue_reviews GROUP BY booking_id HAVING COUNT(*) > 1;
--    -> keep the earliest review per booking, delete extras (or merge), then migrate.
-- 2. Duplicate tournament registrations per (tournament,user):
--    SELECT tournament_id, user_id, COUNT(*) FROM tournament_registrations
--    GROUP BY 1,2 HAVING COUNT(*) > 1;
--    -> keep the earliest registration per pair, delete extras.
-- 3. Backfill sanity after migrate:
--    UPDATE tournaments SET current_participants =
--      (SELECT COUNT(*) FROM tournament_registrations r
--        WHERE r.tournament_id = tournaments.tournament_id);
--    UPDATE coupons SET used_count = 0 WHERE used_count IS NULL; -- (column defaults 0)
-- ROLLBACK: DROP INDEX / ALTER TABLE ... DROP COLUMN statements in reverse order
-- (data in new columns is derived/recoverable; indexes drop cleanly).

-- P2-1: booking payment deadline + expiry scan index.
ALTER TABLE "bookings" ADD COLUMN IF NOT EXISTS "expires_at" TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS "bookings_status_expires_at_idx"
  ON "bookings" ("status", "expires_at");

-- P2-7: refresh rotation chain + lookup index.
ALTER TABLE "refresh_tokens" ADD COLUMN IF NOT EXISTS "jti" TEXT;
ALTER TABLE "refresh_tokens" ADD COLUMN IF NOT EXISTS "family_id" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "refresh_tokens_jti_key" ON "refresh_tokens" ("jti");
CREATE INDEX IF NOT EXISTS "refresh_tokens_user_id_idx" ON "refresh_tokens" ("user_id");

-- P2-5: tournament capacity counter + one-registration-per-user.
ALTER TABLE "tournaments" ADD COLUMN IF NOT EXISTS "current_participants" INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS "tournament_registrations_tournament_id_user_id_key"
  ON "tournament_registrations" ("tournament_id", "user_id");

-- P2-4: coupon global counter + redemption ledger.
ALTER TABLE "coupons" ADD COLUMN IF NOT EXISTS "used_count" INTEGER NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS "coupon_redemptions" (
  "red_id" TEXT NOT NULL,
  "coupon_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "booking_id" UUID NOT NULL,
  "discount_amount" DECIMAL(10,2) NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'applied',
  "used_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "coupon_redemptions_pkey" PRIMARY KEY ("red_id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "coupon_redemptions_coupon_id_user_id_booking_id_key"
  ON "coupon_redemptions" ("coupon_id", "user_id", "booking_id");
CREATE INDEX IF NOT EXISTS "coupon_redemptions_coupon_id_user_id_idx"
  ON "coupon_redemptions" ("coupon_id", "user_id");
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'coupon_redemptions_coupon_id_fkey'
  ) THEN
    ALTER TABLE "coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_coupon_id_fkey"
      FOREIGN KEY ("coupon_id") REFERENCES "coupons"("coupon_id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

-- P2-6: one review per booking.
CREATE UNIQUE INDEX IF NOT EXISTS "venue_reviews_booking_id_key"
  ON "venue_reviews" ("booking_id");
