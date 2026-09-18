-- Which kinds of work a driver takes: local rides, hourly rentals, outstation
-- trips (one-way + round trip). Dispatch only offers a ride to drivers whose
-- set contains the ride's service (see utils/serviceType.js).
ALTER TABLE rt_drivers
  ADD COLUMN service_types SET('local','rental','outstation') NOT NULL DEFAULT 'local'
  AFTER availability;

-- Existing drivers were already getting both local and outstation offers —
-- keep that exact behaviour so nobody silently stops receiving rides.
UPDATE rt_drivers SET service_types = 'local,outstation';

ALTER TABLE rt_rides
  MODIFY ride_type ENUM('local','outstation','round_trip','rental') NOT NULL DEFAULT 'local';
