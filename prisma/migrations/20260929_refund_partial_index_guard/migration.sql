-- Phase 3 real-PostgreSQL finding (2026-09-28, disposable DB proof).
--
-- The Prisma schema language cannot express a PARTIAL unique index, so the
-- constraint below exists ONLY in migration SQL. Any environment built with
-- `prisma db push` (dev clones, fresh test databases) silently LOSES the
-- exactly-one-pending-refund-intent guarantee, and concurrent refund
-- requests could then create multiple pending intents against one booking.
--
-- This guard migration re-asserts the index idempotently so every
-- `migrate deploy` path enforces it. It is a no-op where the Phase 2
-- migration already created it.
--
-- PRE-MIGRATION CHECK (informational; never deletes data):
--   SELECT booking_id, COUNT(*) FROM transactions
--   WHERE txn_type = 'refund' AND txn_status = 'pending'
--   GROUP BY booking_id HAVING COUNT(*) > 1;
-- If that returns rows, a business decision is required before the index
-- can be created; this statement will fail loudly instead of hiding them.

CREATE UNIQUE INDEX IF NOT EXISTS "transactions_one_pending_refund_per_booking"
  ON "transactions" ("booking_id")
  WHERE "txn_type" = 'refund' AND "txn_status" = 'pending';
