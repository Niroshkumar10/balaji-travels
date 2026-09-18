ALTER TABLE rt_rides
  MODIFY ride_type ENUM('local','outstation','round_trip') NOT NULL DEFAULT 'local';

ALTER TABLE rt_drivers DROP COLUMN service_types;
