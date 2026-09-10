-- ============================================================================
--  Two ready-to-drive TEST drivers.
--  Run this in phpMyAdmin (SQL tab) against the `redtaxi` database.
--  Idempotent — safe to run more than once.
--
--  After import: open the driver app, log in with 9000000001 / 9000000002
--  (OTP shows on the screen), then tap "Online".
--
--  Driver 1 : 9000000001  Test Driver One  hatchback  KA01TD1001
--  Driver 2 : 9000000002  Test Driver Two  hatchback  KA01TD1002
-- ============================================================================

-- ── DRIVER 1 : 9000000001 ───────────────────────────────────────────────────
INSERT INTO rt_users (mobile, role, name, status)
VALUES ('9000000001', 'driver', 'Test Driver One', 'active')
ON DUPLICATE KEY UPDATE name = VALUES(name), status = 'active';

INSERT INTO rt_drivers (user_id, kyc_status, license_no, kyc_reviewed_at, availability, is_online)
SELECT id, 'approved', 'DLTEST0000001', NOW(), 'offline', 0
  FROM rt_users WHERE mobile = '9000000001' AND role = 'driver'
ON DUPLICATE KEY UPDATE kyc_status = 'approved', license_no = 'DLTEST0000001', kyc_reviewed_at = NOW();

INSERT INTO rt_driver_wallet (driver_id, balance)
SELECT d.id, 0 FROM rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
 WHERE u.mobile = '9000000001' AND u.role = 'driver'
ON DUPLICATE KEY UPDATE balance = balance;

INSERT INTO rt_vehicles (driver_id, category, make, model, plate_no, color, year, doc_status, is_active)
SELECT d.id, 'hatchback', 'Maruti', 'Swift', 'KA01TD1001', 'White', 2021, 'approved', 1
  FROM rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
 WHERE u.mobile = '9000000001' AND u.role = 'driver'
ON DUPLICATE KEY UPDATE category = VALUES(category), make = VALUES(make), model = VALUES(model),
                        color = VALUES(color), doc_status = 'approved', is_active = 1;

UPDATE rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
  JOIN rt_vehicles v ON v.plate_no = 'KA01TD1001'
   SET d.current_vehicle_id = v.id
 WHERE u.mobile = '9000000001' AND u.role = 'driver';

-- ── DRIVER 2 : 9000000002 ───────────────────────────────────────────────────
INSERT INTO rt_users (mobile, role, name, status)
VALUES ('9000000002', 'driver', 'Test Driver Two', 'active')
ON DUPLICATE KEY UPDATE name = VALUES(name), status = 'active';

INSERT INTO rt_drivers (user_id, kyc_status, license_no, kyc_reviewed_at, availability, is_online)
SELECT id, 'approved', 'DLTEST0000002', NOW(), 'offline', 0
  FROM rt_users WHERE mobile = '9000000002' AND role = 'driver'
ON DUPLICATE KEY UPDATE kyc_status = 'approved', license_no = 'DLTEST0000002', kyc_reviewed_at = NOW();

INSERT INTO rt_driver_wallet (driver_id, balance)
SELECT d.id, 0 FROM rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
 WHERE u.mobile = '9000000002' AND u.role = 'driver'
ON DUPLICATE KEY UPDATE balance = balance;

INSERT INTO rt_vehicles (driver_id, category, make, model, plate_no, color, year, doc_status, is_active)
SELECT d.id, 'hatchback', 'Hyundai', 'i20', 'KA01TD1002', 'Silver', 2021, 'approved', 1
  FROM rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
 WHERE u.mobile = '9000000002' AND u.role = 'driver'
ON DUPLICATE KEY UPDATE category = VALUES(category), make = VALUES(make), model = VALUES(model),
                        color = VALUES(color), doc_status = 'approved', is_active = 1;

UPDATE rt_drivers d
  JOIN rt_users u ON u.id = d.user_id
  JOIN rt_vehicles v ON v.plate_no = 'KA01TD1002'
   SET d.current_vehicle_id = v.id
 WHERE u.mobile = '9000000002' AND u.role = 'driver';

-- ── verify ──────────────────────────────────────────────────────────────────
SELECT u.mobile, u.name, d.id AS driver_id, d.kyc_status, d.is_online,
       d.availability, d.current_vehicle_id, v.category, v.plate_no, v.is_active
  FROM rt_users u
  JOIN rt_drivers d  ON d.user_id = u.id
  LEFT JOIN rt_vehicles v ON v.id = d.current_vehicle_id
 WHERE u.mobile IN ('9000000001', '9000000002');
