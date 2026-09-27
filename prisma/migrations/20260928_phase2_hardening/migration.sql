-- Phase 2 backend hardening. Additive/nullable only; NOT applied to production.
-- Apply with `prisma migrate deploy` ONLY after the pre-migration checks pass.
--
-- PRE-MIGRATION DATA CHECKS (run on a production COPY first; all must return
-- zero rows before proceeding, except where a backfill is documented):
-- 1. Duplicate reviews per booking (blocks §P2-6 unique index):
--    SELECT booking_id, COUNT(*) FROM venue_reviews GROUP BY booking_id HAVING COUNT(*) > 1;
--    -> BUSINESS DECISION REQUIRED: keep the earliest review per booking and
--       remove extras ONLY with product-owner approval. This migration does
--       NOT delete them; the unique index will fail loudly instead.
-- 2. Duplicate tournament registrations per (tournament,user) (blocks §P2-5):
--    SELECT tournament_id, user_id, COUNT(*) FROM tournament_registrations
--    GROUP BY 1,2 HAVING COUNT(*) > 1;
--    -> same policy: manual, approved cleanup only; index fails loudly otherwise.
-- 3. Duplicate slot rows (pre-existing P0 index; re-verify):
--    SELECT venue_id, date, start_time, end_time, COUNT(*) FROM slots
--    GROUP BY 1,2,3,4 HAVING COUNT(*) > 1;
-- 4. Duplicate refresh jti values (new unique; jti is new so only possible if
--    this migration ran partially before — safe to ignore when empty):
--    SELECT jti, COUNT(*) FROM refresh_tokens WHERE jti IS NOT NULL
--    GROUP BY jti HAVING COUNT(*) > 1;
-- 5. Existing transaction/refund rows: no constraint touches them; the new
--    partial unique index only governs FUTURE pending refund intents.
-- 6. Existing notification rows: untouched (no notif schema change; see §P2-9 note).
-- ROLLBACK (reverse order): DROP INDEX ...; ALTER TABLE ... DROP COLUMN ...;
-- new-column data is derived/recoverable; indexes drop cleanly. Never roll
-- back by restoring a dump over live financial tables without a freeze.

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
-- Backfill is IN-MIGRATION (deterministic count of existing registrations),
-- so runtime counters start correct even with historical data.
ALTER TABLE "tournaments" ADD COLUMN IF NOT EXISTS "current_participants" INTEGER NOT NULL DEFAULT 0;
UPDATE "tournaments" t
SET "current_participants" = COALESCE(
  (SELECT COUNT(*) FROM "tournament_registrations" r WHERE r."tournament_id" = t."tournament_id"),
  0
)
WHERE t."current_participants" = 0;
CREATE UNIQUE INDEX IF NOT EXISTS "tournament_registrations_tournament_id_user_id_key"
  ON "tournament_registrations" ("tournament_id", "user_id");

-- P2-4: coupon global counter + redemption ledger.
-- used_count starts at 0. HISTORICAL COUPON USE CANNOT BE RECONSTRUCTED:
-- pre-P2 bookings applied coupons without persisting which code was used
-- (no coupon column on bookings, no redemption table), so any backfilled
-- number would be fabricated. The counter therefore tracks post-migration
-- usage only. RISK ACCEPTED AND DOCUMENTED: coupons with a low remaining
-- budget (usage_limit - historical_use) could overshoot by the unknown
-- historical amount. REQUIRED BUSINESS ACTION before relying on tight
-- usage_limit values: either (a) rotate those coupon codes (issue fresh
-- codes with full budgets), or (b) set used_count manually per code from
-- off-system records. No fake redemption rows are created.
ALTER TABLE "coupons" ADD COLUMN IF NOT EXISTS "used_count" INTEGER NOT NULL DEFAULT 0;
-- Prisma maps red_id @db.Uuid -> PostgreSQL UUID (NOT text).
CREATE TABLE IF NOT EXISTS "coupon_redemptions" (
  "red_id" UUID NOT NULL,
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

-- P2-3: exactly ONE pending refund intent per booking (durable single-flight).
-- Success rows are unrestricted (partial refunds need several). This index is
-- what makes concurrent refund requests converge without Redis.
CREATE UNIQUE INDEX IF NOT EXISTS "transactions_one_pending_refund_per_booking"
  ON "transactions" ("booking_id")
  WHERE "txn_type" = 'refund' AND "txn_status" = 'pending';

-- P2-6: one review per booking (fails loudly on duplicates; see check 1).
CREATE UNIQUE INDEX IF NOT EXISTS "venue_reviews_booking_id_key"
  ON "venue_reviews" ("booking_id");

-- P2-9: durable per-recipient notification dedupe. Nullable: existing rows
-- stay valid and NULL keys never collide, so this is safe on any dataset.
ALTER TABLE "user_notifications" ADD COLUMN IF NOT EXISTS "dedupe_key" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "user_notifications_recipient_id_dedupe_key_key"
  ON "user_notifications" ("recipient_id", "dedupe_key");
