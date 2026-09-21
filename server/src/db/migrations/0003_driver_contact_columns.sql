-- Denormalized copies of the driver's name/mobile onto rt_drivers itself, so
-- the row is self-sufficient for anything reading rt_drivers directly (raw
-- DB browsing, the external Admin Panel) without joining rt_users. The
-- authoritative copies stay on rt_users — application code keeps these two
-- in sync (driverRepo.create() at signup, userRepo.updateProfile() on a name
-- change; mobile never changes after signup, so it's a one-time copy).
--
-- Nullable/additive: existing rows get backfilled once below; nothing reads
-- these columns yet, so this is a pure addition with no behavior change.

ALTER TABLE rt_drivers
  ADD COLUMN name   VARCHAR(120) NULL AFTER user_id,
  ADD COLUMN mobile VARCHAR(20)  NULL AFTER name;

UPDATE rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
   SET d.name = u.name, d.mobile = u.mobile;
