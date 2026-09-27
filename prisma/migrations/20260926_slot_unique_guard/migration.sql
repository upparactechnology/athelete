-- P0: database-level guard against duplicate slot generation races.
-- Pairs with the atomic updateMany reservation in ClientService.createBooking.
-- Safe on existing data ONLY if no duplicates exist; de-duplicate first if
-- this statement fails. Apply with `prisma migrate deploy`. NEEDS RUNTIME TEST.
CREATE UNIQUE INDEX IF NOT EXISTS "slots_venue_id_date_start_time_end_time_key"
  ON "slots" ("venue_id", "date", "start_time", "end_time");
