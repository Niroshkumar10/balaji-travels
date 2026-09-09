-- ===========================================================================
--  RedTaxi - 0001_init
--  Clean ride/trip domain. No healthcare tables, no renamed Microlab tables.
--  Target: MySQL 8.0+ / MariaDB 10.6+ - InnoDB - utf8mb4
--
--  Conventions:
--   - every table: id BIGINT UNSIGNED AUTO_INCREMENT PK, created_at, updated_at
--   - money: DECIMAL(10,2); lat/lng: DECIMAL(10,7)
--   - business refs derived from the AUTO_INCREMENT id (never Date.now())
--   - soft delete via deleted_at only where history must be preserved
-- ===========================================================================

-- -- identity --------------------------------------------------------------
CREATE TABLE rt_users (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mobile         VARCHAR(20)     NOT NULL,
  role           ENUM('customer','driver','admin') NOT NULL,
  name           VARCHAR(120)    NULL,
  email          VARCHAR(160)    NULL,
  status         ENUM('active','blocked','deleted') NOT NULL DEFAULT 'active',
  auth_token     VARCHAR(512)    NULL,
  token_expiry   DATETIME        NULL,
  fcm_token      VARCHAR(512)    NULL,
  last_active_at DATETIME        NULL,
  created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at     DATETIME        NULL,
  PRIMARY KEY (id),
  -- one identity per (mobile, role): the same number may exist as a customer
  -- AND (separately) as a driver, but never twice in the same role.
  UNIQUE KEY uk_users_mobile_role (mobile, role),
  KEY idx_users_mobile (mobile)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rt_customers (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id                BIGINT UNSIGNED NOT NULL,
  default_payment_method ENUM('cash','upi','card','wallet') NOT NULL DEFAULT 'cash',
  home_label             VARCHAR(120)  NULL,
  home_lat               DECIMAL(10,7) NULL,
  home_lng               DECIMAL(10,7) NULL,
  home_addr              VARCHAR(400)  NULL,
  work_label             VARCHAR(120)  NULL,
  work_lat               DECIMAL(10,7) NULL,
  work_lng               DECIMAL(10,7) NULL,
  work_addr              VARCHAR(400)  NULL,
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_customers_user (user_id),
  CONSTRAINT fk_customers_user FOREIGN KEY (user_id) REFERENCES rt_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rt_drivers (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id            BIGINT UNSIGNED NOT NULL,
  kyc_status         ENUM('pending','approved','rejected','suspended') NOT NULL DEFAULT 'pending',
  kyc_reviewed_by    BIGINT UNSIGNED NULL,
  kyc_reviewed_at    DATETIME NULL,
  kyc_reject_reason  VARCHAR(255) NULL,
  license_no         VARCHAR(60)  NULL,
  rating_avg         DECIMAL(3,2) NOT NULL DEFAULT 0.00,
  rating_count       INT UNSIGNED NOT NULL DEFAULT 0,
  is_online          TINYINT(1)   NOT NULL DEFAULT 0,
  availability       ENUM('offline','available','on_trip') NOT NULL DEFAULT 'offline',
  current_vehicle_id BIGINT UNSIGNED NULL,
  last_seen_at       DATETIME NULL,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_drivers_user (user_id),
  KEY idx_drivers_dispatch (is_online, availability, kyc_status),
  CONSTRAINT fk_drivers_user FOREIGN KEY (user_id) REFERENCES rt_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rt_vehicles (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id   BIGINT UNSIGNED NOT NULL,
  category    ENUM('bike','auto','hatchback','sedan','suv') NOT NULL,
  make        VARCHAR(60)  NULL,
  model       VARCHAR(60)  NULL,
  plate_no    VARCHAR(20)  NOT NULL,
  color       VARCHAR(30)  NULL,
  year        SMALLINT UNSIGNED NULL,
  doc_status  ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  is_active   TINYINT(1)   NOT NULL DEFAULT 1,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at  DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_vehicles_plate (plate_no),
  KEY idx_vehicles_driver (driver_id),
  CONSTRAINT fk_vehicles_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE rt_drivers
  ADD CONSTRAINT fk_drivers_vehicle
  FOREIGN KEY (current_vehicle_id) REFERENCES rt_vehicles (id) ON DELETE SET NULL;

-- -- driver location ------------------------------------------------------
-- Last-known position only: ONE row per driver, upserted on every heartbeat /
-- location ping. High-frequency, low-cardinality - this is what the dispatch
-- "nearby drivers" query reads.
CREATE TABLE rt_driver_locations (
  driver_id   BIGINT UNSIGNED NOT NULL,
  lat         DECIMAL(10,7) NOT NULL,
  lng         DECIMAL(10,7) NOT NULL,
  bearing     DECIMAL(6,2)  NULL,
  speed_kmph  DECIMAL(6,2)  NULL,
  accuracy_m  DECIMAL(8,2)  NULL,
  battery     TINYINT UNSIGNED NULL,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (driver_id),
  KEY idx_driver_loc_box (lat, lng),
  KEY idx_driver_loc_updated (updated_at),
  CONSTRAINT fk_driver_loc_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Append-only breadcrumb trail, written only during an active ride at a
-- throttled cadence (NOT on every GPS tick). Kept for dispute resolution / ETA
-- tuning. Prune/partition by month in ops.
CREATE TABLE rt_driver_location_logs (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id  BIGINT UNSIGNED NOT NULL,
  ride_id    BIGINT UNSIGNED NULL,
  lat        DECIMAL(10,7) NOT NULL,
  lng        DECIMAL(10,7) NOT NULL,
  bearing    DECIMAL(6,2)  NULL,
  speed_kmph DECIMAL(6,2)  NULL,
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_dll_ride (ride_id, recorded_at),
  KEY idx_dll_driver (driver_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- fare configuration (pricing rules - data, not code) ------------------
CREATE TABLE rt_fare_configs (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  vehicle_category ENUM('bike','auto','hatchback','sedan','suv') NOT NULL,
  zone             VARCHAR(60)  NOT NULL DEFAULT 'default',
  base_fare        DECIMAL(10,2) NOT NULL,
  included_km      DECIMAL(6,2)  NOT NULL DEFAULT 0,
  per_km           DECIMAL(10,2) NOT NULL,
  per_min          DECIMAL(10,2) NOT NULL DEFAULT 0,
  min_fare         DECIMAL(10,2) NOT NULL,
  waiting_per_min  DECIMAL(10,2) NOT NULL DEFAULT 0,
  free_waiting_min INT UNSIGNED  NOT NULL DEFAULT 3,
  surge_multiplier DECIMAL(4,2)  NOT NULL DEFAULT 1.00,
  night_multiplier DECIMAL(4,2)  NOT NULL DEFAULT 1.00,
  night_start      TIME NULL,
  night_end        TIME NULL,
  cancellation_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
  is_active        TINYINT(1)    NOT NULL DEFAULT 1,
  effective_from   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_fare_cat_zone_active (vehicle_category, zone, is_active, effective_from),
  KEY idx_fare_lookup (vehicle_category, zone, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- promos --------------------------------------------------------------
CREATE TABLE rt_promos (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code           VARCHAR(40) NOT NULL,
  description    VARCHAR(255) NULL,
  type           ENUM('flat','percent') NOT NULL,
  value          DECIMAL(10,2) NOT NULL,
  max_discount   DECIMAL(10,2) NULL,
  min_fare       DECIMAL(10,2) NOT NULL DEFAULT 0,
  usage_limit    INT UNSIGNED NULL,
  per_user_limit INT UNSIGNED NOT NULL DEFAULT 1,
  used_count     INT UNSIGNED NOT NULL DEFAULT 0,
  valid_from     DATETIME NULL,
  valid_to       DATETIME NULL,
  is_active      TINYINT(1) NOT NULL DEFAULT 1,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_promos_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- rides ---------------------------------------------------------------
CREATE TABLE rt_rides (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_ref          VARCHAR(24) NULL,
  customer_id       BIGINT UNSIGNED NOT NULL,
  driver_id         BIGINT UNSIGNED NULL,
  vehicle_id        BIGINT UNSIGNED NULL,
  status            ENUM(
                      'REQUESTED','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ARRIVING',
                      'DRIVER_ARRIVED','RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED',
                      'PAYMENT_PENDING','COMPLETED',
                      'CUSTOMER_CANCELLED','DRIVER_CANCELLED','SYSTEM_CANCELLED',
                      'NO_DRIVERS_FOUND','PAYMENT_FAILED'
                    ) NOT NULL DEFAULT 'REQUESTED',
  ride_type         ENUM('local','outstation','round_trip') NOT NULL DEFAULT 'local',
  vehicle_category  ENUM('bike','auto','hatchback','sedan','suv') NOT NULL,
  pickup_lat        DECIMAL(10,7) NOT NULL,
  pickup_lng        DECIMAL(10,7) NOT NULL,
  pickup_addr       VARCHAR(400) NULL,
  drop_lat          DECIMAL(10,7) NOT NULL,
  drop_lng          DECIMAL(10,7) NOT NULL,
  drop_addr         VARCHAR(400) NULL,
  route_polyline    MEDIUMTEXT NULL,
  distance_m        INT UNSIGNED NULL,
  duration_s        INT UNSIGNED NULL,
  est_fare          DECIMAL(10,2) NULL,
  final_fare        DECIMAL(10,2) NULL,
  fare_breakdown    JSON NULL,
  fare_config_id    BIGINT UNSIGNED NULL,
  promo_id          BIGINT UNSIGNED NULL,
  discount_amount   DECIMAL(10,2) NOT NULL DEFAULT 0,
  payment_id        BIGINT UNSIGNED NULL,
  payment_method    ENUM('cash','upi','card','wallet') NULL,
  otp               CHAR(4) NULL,
  waiting_minutes   INT UNSIGNED NOT NULL DEFAULT 0,
  cancelled_by      ENUM('customer','driver','system') NULL,
  cancel_reason     VARCHAR(255) NULL,
  requested_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  assigned_at       DATETIME NULL,
  driver_arrived_at DATETIME NULL,
  started_at        DATETIME NULL,
  completed_at      DATETIME NULL,
  cancelled_at      DATETIME NULL,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- one live ride per driver: this generated column is the driver_id only
  -- while the ride is in an active (non-terminal, assigned) state, so the
  -- UNIQUE key below makes a second concurrent assignment to the same driver
  -- impossible at the storage level.
  active_driver_id  BIGINT UNSIGNED
    GENERATED ALWAYS AS (
      CASE WHEN status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED',
                           'RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING')
           THEN driver_id ELSE NULL END
    ) STORED,

  PRIMARY KEY (id),
  UNIQUE KEY uk_rides_ref (ride_ref),
  UNIQUE KEY uk_rides_active_driver (active_driver_id),
  KEY idx_rides_customer (customer_id, status, requested_at),
  KEY idx_rides_driver (driver_id, status),
  KEY idx_rides_status (status, requested_at),
  KEY idx_rides_created (created_at),
  CONSTRAINT fk_rides_customer FOREIGN KEY (customer_id) REFERENCES rt_customers (id),
  -- No ON DELETE SET NULL: MariaDB forbids a generated column (active_driver_id)
  -- referencing a column whose FK uses SET NULL/CASCADE. RESTRICT is correct
  -- anyway - a driver with rides is never hard-deleted.
  CONSTRAINT fk_rides_driver   FOREIGN KEY (driver_id)   REFERENCES rt_drivers (id),
  CONSTRAINT fk_rides_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES rt_vehicles (id) ON DELETE SET NULL,
  CONSTRAINT fk_rides_fare     FOREIGN KEY (fare_config_id) REFERENCES rt_fare_configs (id) ON DELETE SET NULL,
  CONSTRAINT fk_rides_promo    FOREIGN KEY (promo_id)    REFERENCES rt_promos (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Every state transition, appended in the same transaction as the ride UPDATE.
CREATE TABLE rt_ride_status_history (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id     BIGINT UNSIGNED NOT NULL,
  from_status VARCHAR(24) NULL,
  to_status   VARCHAR(24) NOT NULL,
  actor       ENUM('customer','driver','system','admin') NOT NULL,
  actor_id    BIGINT UNSIGNED NULL,
  meta        JSON NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_rsh_ride (ride_id, created_at),
  CONSTRAINT fk_rsh_ride FOREIGN KEY (ride_id) REFERENCES rt_rides (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dispatch offer log - one row per (ride, driver) offer.
CREATE TABLE rt_ride_offers (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id      BIGINT UNSIGNED NOT NULL,
  driver_id    BIGINT UNSIGNED NOT NULL,
  status       ENUM('sent','accepted','rejected','timed_out','superseded') NOT NULL DEFAULT 'sent',
  distance_m   INT UNSIGNED NULL,
  sent_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_offer_ride_driver (ride_id, driver_id),
  KEY idx_offer_ride (ride_id, status),
  KEY idx_offer_driver (driver_id, status),
  CONSTRAINT fk_offer_ride   FOREIGN KEY (ride_id)   REFERENCES rt_rides (id) ON DELETE CASCADE,
  CONSTRAINT fk_offer_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- payments ------------------------------------------------------------
CREATE TABLE rt_payments (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_ref        VARCHAR(28) NULL,
  ride_id            BIGINT UNSIGNED NOT NULL,
  customer_id        BIGINT UNSIGNED NOT NULL,
  method             ENUM('cash','upi','card','wallet') NOT NULL,
  amount             DECIMAL(10,2) NOT NULL,
  currency           CHAR(3) NOT NULL DEFAULT 'INR',
  status             ENUM('pending','authorized','paid','failed','refunded') NOT NULL DEFAULT 'pending',
  gateway            VARCHAR(30) NULL,
  gateway_order_id   VARCHAR(80) NULL,
  gateway_payment_id VARCHAR(80) NULL,
  idempotency_key    VARCHAR(80) NULL,
  attempts           INT UNSIGNED NOT NULL DEFAULT 0,
  failure_reason     VARCHAR(255) NULL,
  paid_at            DATETIME NULL,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  -- exactly one successful charge per ride, forever: this column holds the
  -- ride_id only for a 'paid' row, and is UNIQUE.
  paid_ride_id       BIGINT UNSIGNED
    GENERATED ALWAYS AS (CASE WHEN status = 'paid' THEN ride_id ELSE NULL END) STORED,

  PRIMARY KEY (id),
  UNIQUE KEY uk_payments_ref (payment_ref),
  UNIQUE KEY uk_payments_paid_ride (paid_ride_id),
  UNIQUE KEY uk_payments_idem (idempotency_key),
  UNIQUE KEY uk_payments_gw_order (gateway_order_id),
  UNIQUE KEY uk_payments_gw_payment (gateway_payment_id),
  KEY idx_payments_ride (ride_id),
  KEY idx_payments_customer (customer_id),
  CONSTRAINT fk_payments_ride     FOREIGN KEY (ride_id)     REFERENCES rt_rides (id),
  CONSTRAINT fk_payments_customer FOREIGN KEY (customer_id) REFERENCES rt_customers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE rt_rides
  ADD CONSTRAINT fk_rides_payment FOREIGN KEY (payment_id) REFERENCES rt_payments (id) ON DELETE SET NULL;

-- Idempotent webhook / gateway-callback log.
CREATE TABLE rt_payment_events (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_id   BIGINT UNSIGNED NULL,
  event_id     VARCHAR(120) NOT NULL,
  event_type   VARCHAR(60)  NULL,
  payload      JSON NULL,
  processed_at DATETIME NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_pevent_event (event_id),
  KEY idx_pevent_payment (payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- driver earnings -----------------------------------------------------
CREATE TABLE rt_driver_wallet (
  driver_id  BIGINT UNSIGNED NOT NULL,
  balance    DECIMAL(12,2) NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (driver_id),
  CONSTRAINT fk_wallet_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rt_wallet_ledger (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id     BIGINT UNSIGNED NOT NULL,
  ride_id       BIGINT UNSIGNED NULL,
  type          ENUM('trip_earning','commission','incentive','payout','adjustment') NOT NULL,
  amount        DECIMAL(12,2) NOT NULL,           -- signed: credits +, debits -
  balance_after DECIMAL(12,2) NOT NULL,
  ref           VARCHAR(60) NULL,
  note          VARCHAR(255) NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ledger_driver (driver_id, created_at),
  KEY idx_ledger_ride (ride_id),
  CONSTRAINT fk_ledger_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rt_payouts (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id    BIGINT UNSIGNED NOT NULL,
  amount       DECIMAL(12,2) NOT NULL,
  status       ENUM('requested','processing','paid','failed') NOT NULL DEFAULT 'requested',
  gateway_ref  VARCHAR(80) NULL,
  requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at DATETIME NULL,
  PRIMARY KEY (id),
  KEY idx_payouts_driver (driver_id, status),
  CONSTRAINT fk_payouts_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- ratings -------------------------------------------------------------
CREATE TABLE rt_ratings (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id    BIGINT UNSIGNED NOT NULL,
  rated_by   ENUM('customer','driver') NOT NULL,
  rater_user_id BIGINT UNSIGNED NOT NULL,
  ratee_user_id BIGINT UNSIGNED NOT NULL,
  stars      TINYINT UNSIGNED NOT NULL,
  comment    VARCHAR(500) NULL,
  tags       JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_rating_ride_by (ride_id, rated_by),
  KEY idx_rating_ratee (ratee_user_id),
  CONSTRAINT fk_rating_ride FOREIGN KEY (ride_id) REFERENCES rt_rides (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- promo redemptions ---------------------------------------------------
CREATE TABLE rt_promo_redemptions (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  promo_id   BIGINT UNSIGNED NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  ride_id    BIGINT UNSIGNED NOT NULL,
  discount   DECIMAL(10,2) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_redemption_promo_ride (promo_id, ride_id),
  KEY idx_redemption_user_promo (user_id, promo_id),
  CONSTRAINT fk_redemption_promo FOREIGN KEY (promo_id) REFERENCES rt_promos (id) ON DELETE CASCADE,
  CONSTRAINT fk_redemption_ride  FOREIGN KEY (ride_id)  REFERENCES rt_rides (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- saved places --------------------------------------------------------
CREATE TABLE rt_saved_places (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id BIGINT UNSIGNED NOT NULL,
  label       VARCHAR(80) NOT NULL,
  lat         DECIMAL(10,7) NOT NULL,
  lng         DECIMAL(10,7) NOT NULL,
  addr        VARCHAR(400) NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_places_customer (customer_id),
  CONSTRAINT fk_places_customer FOREIGN KEY (customer_id) REFERENCES rt_customers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- notifications -------------------------------------------------------
CREATE TABLE rt_notifications (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  type       VARCHAR(50) NOT NULL,
  title      VARCHAR(160) NOT NULL,
  body       VARCHAR(500) NULL,
  data       JSON NULL,
  read_at    DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notif_user (user_id, created_at),
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES rt_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- OTP challenges ------------------------------------------------------
CREATE TABLE rt_otps (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mobile      VARCHAR(20) NOT NULL,
  role        ENUM('customer','driver','admin') NOT NULL,
  code_hash   CHAR(64) NOT NULL,               -- sha256(code + mobile + secret)
  expires_at  DATETIME NOT NULL,
  attempts    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  consumed_at DATETIME NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_otp_lookup (mobile, role, consumed_at, expires_at),
  KEY idx_otp_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- admin audit ---------------------------------------------------------
CREATE TABLE rt_admin_audit (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  admin_id   BIGINT UNSIGNED NULL,
  action     VARCHAR(80) NOT NULL,
  entity     VARCHAR(60) NOT NULL,
  entity_id  VARCHAR(60) NULL,
  before_val JSON NULL,
  after_val  JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_entity (entity, entity_id),
  KEY idx_audit_admin (admin_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
