-- Driver availability gains a `reserved` state, distinct from `on_trip`,
-- for a driver who has accepted a future Rental/Outstation/Trip booking but
-- hasn't started it yet (see driverRepo.recomputeAvailability()). Also adds
-- the accept/decline gate columns that let a driver explicitly confirm an
-- admin-assigned Rental/Trip before it's treated as accepted, independent
-- of whichever ADMIN_ASSIGNMENT_MODE assigned them (see assignmentGateService.js).
--
-- Finally, narrows rt_rides.active_driver_id's generated expression so the
-- exclusive "currently claimed" slot is taken at DRIVER_ASSIGNED only for
-- Local, and at DRIVER_ARRIVING (i.e. the driver has tapped Start
-- Navigation) for everything else. This is what lets a driver be
-- simultaneously RESERVED on a future non-local booking (DRIVER_ASSIGNED,
-- not yet occupying the unique slot) and ON_TRIP on a live Local ride
-- (which does) -- structurally impossible under the old definition, where
-- DRIVER_ASSIGNED alone claimed the slot for every ride type. The new
-- predicate is a strict subset of the old one (removes non-local
-- DRIVER_ASSIGNED, adds nothing), so no existing row flips from NULL to
-- non-NULL and the UNIQUE key cannot fail to re-add on real data.
--
-- NOTE: this migration is NOT safely atomic. `migrate.js` wraps it in
-- START TRANSACTION/COMMIT, but the ALTER TABLE statements below (enum
-- MODIFY, column ADD/DROP, generated-column rebuild) each auto-commit DDL
-- in MySQL/MariaDB regardless of that wrapper, and the column rebuild is a
-- full table copy (ALGORITHM=COPY). Run during a maintenance window; a
-- tested 0004_reserved_availability.down.sql exists to reverse it.

-- 1) the new driver availability state
ALTER TABLE rt_drivers
  MODIFY COLUMN availability
    ENUM('offline','available','reserved','on_trip') NOT NULL DEFAULT 'offline';
-- idx_drivers_dispatch (is_online, availability, kyc_status) is unaffected.

-- 2) the accept/decline gate. `driver_accepted_by` (not just a timestamp)
-- means a stale acceptance is automatically invalidated if driver_id is
-- ever re-pointed to a different driver (e.g. the external panel
-- reassigning) -- no extra bookkeeping needed to detect that case.
ALTER TABLE rt_rides
  ADD COLUMN driver_accepted_at DATETIME NULL AFTER assigned_at,
  ADD COLUMN driver_accepted_by BIGINT UNSIGNED NULL AFTER driver_accepted_at;

-- 3) grandfather every in-flight non-local assignment as already accepted,
-- so a live booking never regresses to "waiting for driver confirmation"
-- and its driver isn't asked to re-accept something already under way.
UPDATE rt_rides
   SET driver_accepted_at = COALESCE(assigned_at, updated_at),
       driver_accepted_by = driver_id
 WHERE driver_id IS NOT NULL
   AND ride_type <> 'local'
   AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED',
                  'RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING');

-- 4) the generated-column rebuild (drop + re-add; MariaDB/MySQL don't allow
-- altering a STORED generated column's expression in place).
ALTER TABLE rt_rides DROP INDEX uk_rides_active_driver;
ALTER TABLE rt_rides DROP COLUMN active_driver_id;
ALTER TABLE rt_rides
  ADD COLUMN active_driver_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (
      CASE
        WHEN status IN ('DRIVER_ARRIVING','DRIVER_ARRIVED','RIDE_STARTED',
                        'RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING')
          THEN driver_id
        WHEN status = 'DRIVER_ASSIGNED' AND ride_type = 'local'
          THEN driver_id
        ELSE NULL
      END
    ) STORED;
ALTER TABLE rt_rides ADD UNIQUE KEY uk_rides_active_driver (active_driver_id);

-- 5) backfill availability for drivers now holding an (already-accepted,
-- per step 3) reservation and nothing live.
UPDATE rt_drivers d
   SET d.availability = 'reserved'
 WHERE d.is_online = 1
   AND d.availability = 'available'
   AND NOT EXISTS (SELECT 1 FROM rt_rides r WHERE r.active_driver_id = d.id)
   AND EXISTS (SELECT 1 FROM rt_rides r
                WHERE r.driver_id = d.id AND r.status = 'DRIVER_ASSIGNED'
                  AND r.ride_type <> 'local' AND r.driver_accepted_by = d.id);
