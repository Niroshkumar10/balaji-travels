-- Only safe to run once no driver is currently 'reserved' and no ride has
-- a non-NULL driver_accepted_at (i.e. nothing depends on the new gate).

-- 1) restore the original active_driver_id definition.
ALTER TABLE rt_rides DROP INDEX uk_rides_active_driver;
ALTER TABLE rt_rides DROP COLUMN active_driver_id;
ALTER TABLE rt_rides
  ADD COLUMN active_driver_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (
      CASE WHEN status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED',
                           'RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING')
           THEN driver_id ELSE NULL END
    ) STORED;
ALTER TABLE rt_rides ADD UNIQUE KEY uk_rides_active_driver (active_driver_id);

-- 2) drop the accept/decline gate columns.
ALTER TABLE rt_rides
  DROP COLUMN driver_accepted_at,
  DROP COLUMN driver_accepted_by;

-- 3) narrow availability back (any 'reserved' driver must be resolved first).
UPDATE rt_drivers SET availability = 'available' WHERE availability = 'reserved';
ALTER TABLE rt_drivers
  MODIFY COLUMN availability
    ENUM('offline','available','on_trip') NOT NULL DEFAULT 'offline';
