-- Rental packages (hourly/km bundles, priced off the existing fare formula —
-- see server/src/services/rentalService.js) and real scheduled dispatch
-- (a ride booked for a future date/time actually waits instead of
-- dispatching immediately — see server/src/jobs/scheduledDispatch.js).
--
-- Additive/backward-compatible: existing rows default to ride_type='local'
-- (unchanged) and scheduled_at/rental_package_hours NULL (unchanged
-- immediate-dispatch behavior for every ride created before this migration
-- and every non-rental ride created after it).

ALTER TABLE rt_rides
  MODIFY COLUMN ride_type ENUM('local','outstation','round_trip','rental') NOT NULL DEFAULT 'local';

ALTER TABLE rt_rides
  ADD COLUMN scheduled_at DATETIME NULL AFTER requested_at,
  ADD COLUMN rental_package_hours TINYINT UNSIGNED NULL AFTER scheduled_at;

-- scheduledDispatch job polls for exactly this: REQUESTED rides whose time
-- has arrived. Composite index keeps that a cheap, index-only scan instead
-- of a full table scan as rt_rides grows.
ALTER TABLE rt_rides
  ADD INDEX idx_rides_scheduled (status, scheduled_at);
