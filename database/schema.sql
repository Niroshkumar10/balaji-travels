-- ===========================================================================
--   RedTaxi -- Database Design (authoritative schema)
--   Ride-hailing platform: customer app | driver app | backend | admin web
-- ===========================================================================
--
-- Target      : MySQL 8.0+  /  MariaDB 10.6+     (InnoDB, utf8mb4)
-- Character set: utf8mb4 / utf8mb4_0900_ai_ci (MySQL) - utf8mb4_general_ci on MariaDB
--
-- HOW TO APPLY
--   mysql -u root -p                                  \
--     -e "CREATE DATABASE redtaxi CHARACTER SET utf8mb4;"
--   mysql -u root -p redtaxi < database/schema.sql
--
--   The backend's migration runner (server/src/db/migrate.js) applies the
--   identical DDL from server/src/db/migrations/0001_init.sql. This file is the
--   human-readable design of record; keep the two in sync.
--
-- CONVENTIONS
--   * Table prefix `rt_` - a clean ride domain. No healthcare tables, no
--     renamed Microlab tables.
--   * Every table: `id BIGINT UNSIGNED AUTO_INCREMENT` PK (except the two
--     natural-key tables `rt_driver_locations` / `rt_driver_wallet`, keyed by
--     `driver_id`), plus `created_at` and - where rows are mutated - `updated_at`.
--   * Money   : DECIMAL(10,2)  (wallet balances DECIMAL(12,2)).
--   * Lat/Lng : DECIMAL(10,7)  (~1 cm precision).
--   * Human-facing references (ride_ref, payment_ref ...) are DERIVED FROM the
--     row's AUTO_INCREMENT id, never from Date.now(). Microlab's load tests
--     proved timestamp-only ids collide under concurrency (booking_ref ~31%
--     failure at 500 users; family visit_group_id bleeding across customers).
--   * Soft delete (`deleted_at`) only where history must survive a delete
--     (users, vehicles, rides are hard-referenced elsewhere).
--   * Timestamps stored in UTC; the apps localise.
--
-- TWO INTEGRITY GUARANTEES ENFORCED BY THE SCHEMA ITSELF (not just app code)
--   1. A driver can hold AT MOST ONE active ride.
--      rt_rides.active_driver_id is a STORED generated column = driver_id while
--      the ride is in an assigned/active state, else NULL, with a UNIQUE key.
--      A second concurrent assignment to the same driver fails at INSERT/UPDATE.
--   2. A ride can have AT MOST ONE successful payment, forever.
--      rt_payments.paid_ride_id is a STORED generated column = ride_id only when
--      status='paid', else NULL, with a UNIQUE key. A duplicate successful
--      charge fails at the storage layer regardless of app bugs or webhook
--      replays. (Microlab load test PAY-01: 790 real overpaid bookings.)
--
-- FK DEPENDENCY ORDER (why tables appear in this sequence)
--   rt_users -> rt_customers / rt_drivers -> rt_vehicles -> (rt_drivers.current_vehicle_id)
--   -> rt_fare_configs, rt_promos -> rt_rides -> rt_ride_* , rt_payments
--   -> rt_payments (rt_rides.payment_id back-reference) -> wallet / ledger / payouts
--   -> ratings, redemptions, saved places, notifications, otps, audit.
--   Circular refs (rt_drivers<->rt_vehicles, rt_rides<->rt_payments) are closed
--   with ALTER TABLE after both sides exist.
--
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- Drop-first so this file is safe to re-import (DROP TABLE is allowed even where
-- DROP DATABASE is disabled by the hosting panel). All CREATEs below assume a
-- clean slate - there is no CREATE TABLE IF NOT EXISTS except rt_schema_migrations.
--
-- IMPORTANT for phpMyAdmin: on the Import page, UNCHECK "Enable foreign key
-- checks" so the SET FOREIGN_KEY_CHECKS = 0 above is respected. Two circular
-- refs (rt_drivers<->rt_vehicles, rt_rides<->rt_payments) make a plain ordered
-- DROP impossible with FK checks forced on. Order below is child-first as a
-- best effort regardless.
DROP TABLE IF EXISTS
  rt_schema_migrations, rt_admin_audit, rt_otps, rt_notifications,
  rt_saved_places, rt_promo_redemptions, rt_ratings,
  rt_payouts, rt_wallet_ledger, rt_driver_wallet, rt_payment_events,
  rt_ride_offers, rt_ride_status_history, rt_payments, rt_rides,
  rt_driver_location_logs, rt_driver_locations, rt_vehicles,
  rt_drivers, rt_customers, rt_fare_configs, rt_promos, rt_users;

SET FOREIGN_KEY_CHECKS = 1;


-- =============================================================================
--  1.  IDENTITY  -  rt_users / rt_customers / rt_drivers / rt_vehicles
-- =============================================================================

-- rt_users - one identity row per (mobile, role).
--   The same phone number may exist BOTH as a customer and (separately) as a
--   driver - different apps, different profiles - but never twice in one role.
--   `auth_token` holds the currently-valid JWT: middleware compares the
--   presented token against this column on every request, so logout / "logged
--   in on a new device" revokes instantly instead of waiting for JWT expiry.
--   Client-sent role is never trusted - role is fixed here at first login.
CREATE TABLE rt_users (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mobile         VARCHAR(20)     NOT NULL,
  role           ENUM('customer','driver','admin') NOT NULL,
  name           VARCHAR(120)    NULL,
  email          VARCHAR(160)    NULL,
  status         ENUM('active','blocked','deleted') NOT NULL DEFAULT 'active',
  auth_token     VARCHAR(512)    NULL,               -- current session JWT (live check)
  token_expiry   DATETIME        NULL,
  fcm_token      VARCHAR(512)    NULL,               -- push target for this identity
  last_active_at DATETIME        NULL,
  created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at     DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_mobile_role (mobile, role),   -- the identity rule
  KEY idx_users_mobile (mobile)                     -- "is this number known at all?"
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_customers - customer-role profile. 1:1 with a role='customer' user.
--   home_/work_ are the saved shortcuts shown on the booking screen.
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

-- rt_drivers - driver-role profile. 1:1 with a role='driver' user.
--   kyc_status gates dispatch eligibility (admin approves/rejects/suspends).
--   is_online + availability are the dispatch filter; `availability='on_trip'`
--   is written ONLY by the atomic ride-assignment path (never by presence
--   updates) so it can't drift.
--   rating_avg / rating_count are denormalised running aggregates, updated in
--   the same txn a rating is inserted (avoids an AVG() scan on every dispatch).
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
  last_seen_at       DATETIME NULL,                  -- last heartbeat; offline-sweep input
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_drivers_user (user_id),
  KEY idx_drivers_dispatch (is_online, availability, kyc_status),  -- candidate filter
  CONSTRAINT fk_drivers_user FOREIGN KEY (user_id) REFERENCES rt_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_vehicles - a driver's vehicle(s). category drives fare + which ride
--   requests the driver is eligible for. plate_no globally unique.
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

-- close the rt_drivers -> rt_vehicles cycle now that both tables exist
ALTER TABLE rt_drivers
  ADD CONSTRAINT fk_drivers_vehicle
  FOREIGN KEY (current_vehicle_id) REFERENCES rt_vehicles (id) ON DELETE SET NULL;


-- =============================================================================
--  2.  DRIVER LOCATION
-- =============================================================================

-- rt_driver_locations - LAST-KNOWN position only. Exactly one row per driver,
--   UPSERTed on every heartbeat / location ping. This is the hot table the
--   dispatch "nearby available drivers" query reads. Keeping it single-row-per
--   -driver means that query touches at most (#online drivers) rows.
--   Nearby query pattern (bounding box + Haversine, ORDER BY distance LIMIT n):
--     WHERE lat BETWEEN :latMin AND :latMax AND lng BETWEEN :lngMin AND :lngMax
--     -> idx_driver_loc_box narrows the scan; distance is computed on the
--       survivors. Verify the plan with EXPLAIN before Phase 10 sign-off; add a
--       POINT + SPATIAL index if the box scan ever gets hot.
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
  KEY idx_driver_loc_updated (updated_at),          -- stale-location sweep
  CONSTRAINT fk_driver_loc_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_driver_location_logs - append-only breadcrumb trail. Written ONLY during
--   an active ride, at a THROTTLED cadence (e.g. one row / 5 s or / 50 m moved)
--   - never on every raw GPS tick. Purpose: dispute resolution, ETA tuning,
--   replay. Ops should partition/prune by month.
CREATE TABLE rt_driver_location_logs (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id   BIGINT UNSIGNED NOT NULL,
  ride_id     BIGINT UNSIGNED NULL,
  lat         DECIMAL(10,7) NOT NULL,
  lng         DECIMAL(10,7) NOT NULL,
  bearing     DECIMAL(6,2)  NULL,
  speed_kmph  DECIMAL(6,2)  NULL,
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_dll_ride (ride_id, recorded_at),          -- "draw this ride's path"
  KEY idx_dll_driver (driver_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
--  3.  PRICING RULES  (data, not code - change fares without a deploy)
-- =============================================================================

-- rt_fare_configs - one active row per (vehicle_category, zone). The backend
--   fare engine is the ONLY authority on the payable amount; the app shows an
--   estimate from these numbers but the server recomputes the final fare from
--   actual distance/time at ride completion. Clients cannot submit a fare.
--     fare = max(min_fare,
--                base_fare
--              + per_km * max(0, distance_km - included_km)
--              + per_min * duration_min
--              + waiting_per_min * max(0, waiting_min - free_waiting_min))
--            * surge_multiplier * (night window ? night_multiplier : 1)
--            - promo_discount
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

-- rt_promos - discount codes. `used_count` is a running counter bumped in the
--   same txn as a redemption; `usage_limit` / `per_user_limit` are enforced in
--   application logic against rt_promo_redemptions.
CREATE TABLE rt_promos (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code           VARCHAR(40) NOT NULL,
  description    VARCHAR(255) NULL,
  type           ENUM('flat','percent') NOT NULL,
  value          DECIMAL(10,2) NOT NULL,             -- Rs off (flat) or % (percent)
  max_discount   DECIMAL(10,2) NULL,                 -- cap for percent promos
  min_fare       DECIMAL(10,2) NOT NULL DEFAULT 0,
  usage_limit    INT UNSIGNED NULL,                  -- global; NULL = unlimited
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


-- =============================================================================
--  4.  RIDES  -  the core aggregate + its state machine
-- =============================================================================

-- rt_rides
--   status ENUM = the ride state machine. Legal transitions are enforced in
--   server/src/services/rideStateMachine.js (the ONLY code that writes this
--   column), inside a txn that also appends rt_ride_status_history. Invalid
--   transitions (e.g. COMPLETED -> DRIVER_ARRIVING) are rejected with 409.
--
--     REQUESTED -> SEARCHING_DRIVER -> DRIVER_ASSIGNED -> DRIVER_ARRIVING
--       -> DRIVER_ARRIVED -> RIDE_STARTED -> RIDE_IN_PROGRESS -> DRIVER_COMPLETED
--       -> PAYMENT_PENDING -> COMPLETED
--     branches: NO_DRIVERS_FOUND - PAYMENT_FAILED(->retry->PAYMENT_PENDING)
--     cancels : CUSTOMER_CANCELLED - DRIVER_CANCELLED - SYSTEM_CANCELLED
--
--   final_fare / fare_breakdown are written by the backend fare engine at
--   DRIVER_COMPLETED; the client never supplies them.
--   otp - 4-digit code the customer shows the driver; RIDE_STARTED transition
--   guard checks it. Cleared after the ride starts.
--
--   active_driver_id  (STORED generated column)
--     = driver_id  WHILE the ride is assigned/active, else NULL.
--     UNIQUE(active_driver_id) => a driver physically cannot be attached to two
--     live rides at once. This is guarantee #1 from the header - the storage
--     engine enforces it even if two accepts race past the app checks.
CREATE TABLE rt_rides (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_ref          VARCHAR(24) NULL,                -- 'RIDE-00000042', set post-insert
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
  route_polyline    MEDIUMTEXT NULL,                 -- encoded polyline from Directions
  distance_m        INT UNSIGNED NULL,
  duration_s        INT UNSIGNED NULL,
  est_fare          DECIMAL(10,2) NULL,
  final_fare        DECIMAL(10,2) NULL,
  fare_breakdown    JSON NULL,                       -- {base, distance, time, waiting, surge, night, discount}
  fare_config_id    BIGINT UNSIGNED NULL,
  promo_id          BIGINT UNSIGNED NULL,
  discount_amount   DECIMAL(10,2) NOT NULL DEFAULT 0,
  payment_id        BIGINT UNSIGNED NULL,            -- back-ref, FK added after rt_payments
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

  active_driver_id  BIGINT UNSIGNED
    GENERATED ALWAYS AS (
      CASE WHEN status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED',
                           'RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING')
           THEN driver_id ELSE NULL END
    ) STORED,

  PRIMARY KEY (id),
  UNIQUE KEY uk_rides_ref (ride_ref),
  UNIQUE KEY uk_rides_active_driver (active_driver_id),      -- guarantee #1
  KEY idx_rides_customer (customer_id, status, requested_at),-- customer history / active ride
  KEY idx_rides_driver   (driver_id, status),                -- driver active ride / history
  KEY idx_rides_status   (status, requested_at),             -- dispatch queue / admin monitor
  KEY idx_rides_created  (created_at),
  CONSTRAINT fk_rides_customer FOREIGN KEY (customer_id) REFERENCES rt_customers (id),
  -- No ON DELETE SET NULL here: MariaDB (unlike MySQL 8) forbids a generated
  -- column (active_driver_id) from referencing a column whose FK uses SET NULL
  -- / CASCADE. RESTRICT is also the correct behaviour - a driver with ride
  -- history is never hard-deleted (suspend via kyc_status instead).
  CONSTRAINT fk_rides_driver   FOREIGN KEY (driver_id)   REFERENCES rt_drivers (id),
  CONSTRAINT fk_rides_vehicle  FOREIGN KEY (vehicle_id)  REFERENCES rt_vehicles (id)  ON DELETE SET NULL,
  CONSTRAINT fk_rides_fare     FOREIGN KEY (fare_config_id) REFERENCES rt_fare_configs (id) ON DELETE SET NULL,
  CONSTRAINT fk_rides_promo    FOREIGN KEY (promo_id)    REFERENCES rt_promos (id)     ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_ride_status_history - append-only audit of every transition. Written in
--   the SAME transaction as the rt_rides UPDATE, so the two can never diverge.
--   This is the source of truth for "what happened when" and for reconstructing
--   ride state after a client reconnects.
CREATE TABLE rt_ride_status_history (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id     BIGINT UNSIGNED NOT NULL,
  from_status VARCHAR(24) NULL,
  to_status   VARCHAR(24) NOT NULL,
  actor       ENUM('customer','driver','system','admin') NOT NULL,
  actor_id    BIGINT UNSIGNED NULL,
  meta        JSON NULL,                             -- {reason, lat, lng, etaSec, ...}
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_rsh_ride (ride_id, created_at),
  CONSTRAINT fk_rsh_ride FOREIGN KEY (ride_id) REFERENCES rt_rides (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_ride_offers - the dispatch offer log: one row per (ride, driver) the
--   engine pinged. Replaces Microlab's ip_booking_requests. Lifecycle:
--     sent -> accepted | rejected | timed_out | superseded
--   UNIQUE(ride_id, driver_id) means a driver is offered a given ride once.
--   The WINNER is decided by the atomic UPDATE on rt_rides (see app note
--   below), not by writing 'accepted' here - this row is updated afterwards.
CREATE TABLE rt_ride_offers (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id      BIGINT UNSIGNED NOT NULL,
  driver_id    BIGINT UNSIGNED NOT NULL,
  status       ENUM('sent','accepted','rejected','timed_out','superseded') NOT NULL DEFAULT 'sent',
  distance_m   INT UNSIGNED NULL,                    -- driver->pickup at offer time
  sent_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_offer_ride_driver (ride_id, driver_id),
  KEY idx_offer_ride   (ride_id, status),
  KEY idx_offer_driver (driver_id, status),
  CONSTRAINT fk_offer_ride   FOREIGN KEY (ride_id)   REFERENCES rt_rides (id)   ON DELETE CASCADE,
  CONSTRAINT fk_offer_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -- RACE-SAFE ASSIGNMENT (application note - no DDL) --------------------------
--   On `ride:offer_response {accept:true}` the server runs, in ONE transaction:
--     UPDATE rt_rides
--        SET driver_id=:d, vehicle_id=:v, status='DRIVER_ASSIGNED', assigned_at=NOW()
--      WHERE id=:ride AND status='SEARCHING_DRIVER' AND driver_id IS NULL;
--     -- affectedRows === 0  -> another driver already won -> ROLLBACK, tell this
--     --                       driver "ride already taken". Exactly one winner.
--     UPDATE rt_drivers SET availability='on_trip'
--      WHERE id=:d AND availability='available';   -- 0 rows -> driver already busy -> ROLLBACK
--     INSERT rt_ride_status_history ...;
--     UPDATE rt_ride_offers SET status='accepted'   WHERE ride_id=:ride AND driver_id=:d;
--     UPDATE rt_ride_offers SET status='superseded' WHERE ride_id=:ride AND status='sent';
--   A short Redis `SET NX` lock on ride:<id> just makes the losing side cheap;
--   the WHERE-clause guard above is the real correctness boundary and holds
--   across N app instances with no Redis.


-- =============================================================================
--  5.  PAYMENTS
-- =============================================================================

-- rt_payments - one payment attempt per row.
--   Idempotency, three layers:
--     * idempotency_key  UNIQUE - the client sends `Idempotency-Key`; a retried
--       "create payment" with the same key returns the same row, never a 2nd charge.
--     * gateway_order_id / gateway_payment_id UNIQUE - the gateway's own ids
--       can't be recorded twice (webhook replay safe).
--     * paid_ride_id (STORED generated = ride_id only when status='paid') UNIQUE
--       - guarantee #2: a ride can never have two 'paid' rows, whatever the app
--       or a duplicate webhook does. (Microlab PAY-01: 790 real overpaid rows.)
--   The payable `amount` is set by the backend from the ride's final_fare - the
--   client-reported amount is never trusted.
CREATE TABLE rt_payments (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_ref        VARCHAR(28) NULL,               -- 'PAY-00000042'
  ride_id            BIGINT UNSIGNED NOT NULL,
  customer_id        BIGINT UNSIGNED NOT NULL,
  method             ENUM('cash','upi','card','wallet') NOT NULL,
  amount             DECIMAL(10,2) NOT NULL,
  currency           CHAR(3) NOT NULL DEFAULT 'INR',
  status             ENUM('pending','authorized','paid','failed','refunded') NOT NULL DEFAULT 'pending',
  gateway            VARCHAR(30) NULL,               -- 'razorpay' | NULL for cash
  gateway_order_id   VARCHAR(80) NULL,
  gateway_payment_id VARCHAR(80) NULL,
  idempotency_key    VARCHAR(80) NULL,
  attempts           INT UNSIGNED NOT NULL DEFAULT 0,
  failure_reason     VARCHAR(255) NULL,
  paid_at            DATETIME NULL,
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  paid_ride_id       BIGINT UNSIGNED
    GENERATED ALWAYS AS (CASE WHEN status = 'paid' THEN ride_id ELSE NULL END) STORED,

  PRIMARY KEY (id),
  UNIQUE KEY uk_payments_ref        (payment_ref),
  UNIQUE KEY uk_payments_paid_ride  (paid_ride_id),  -- guarantee #2
  UNIQUE KEY uk_payments_idem       (idempotency_key),
  UNIQUE KEY uk_payments_gw_order   (gateway_order_id),
  UNIQUE KEY uk_payments_gw_payment (gateway_payment_id),
  KEY idx_payments_ride     (ride_id),
  KEY idx_payments_customer (customer_id),
  CONSTRAINT fk_payments_ride     FOREIGN KEY (ride_id)     REFERENCES rt_rides (id),
  CONSTRAINT fk_payments_customer FOREIGN KEY (customer_id) REFERENCES rt_customers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- close the rt_rides -> rt_payments cycle
ALTER TABLE rt_rides
  ADD CONSTRAINT fk_rides_payment FOREIGN KEY (payment_id) REFERENCES rt_payments (id) ON DELETE SET NULL;

-- rt_payment_events - every gateway webhook / callback, deduped by the
--   gateway's own event id. Processing checks `processed_at` so a replayed
--   webhook is a no-op.
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


-- =============================================================================
--  6.  DRIVER EARNINGS  (wallet + immutable ledger + payouts)
-- =============================================================================

-- rt_driver_wallet - running balance, one row per driver (created with the
--   driver). Every change to `balance` is mirrored by a rt_wallet_ledger row in
--   the same txn, so the ledger always sums to the balance.
CREATE TABLE rt_driver_wallet (
  driver_id  BIGINT UNSIGNED NOT NULL,
  balance    DECIMAL(12,2) NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (driver_id),
  CONSTRAINT fk_wallet_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_wallet_ledger - immutable, append-only. `amount` is signed (credit +,
--   debit -). `balance_after` snapshots the wallet balance right after this
--   entry, so a statement can be rendered without re-summing.
CREATE TABLE rt_wallet_ledger (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  driver_id     BIGINT UNSIGNED NOT NULL,
  ride_id       BIGINT UNSIGNED NULL,
  type          ENUM('trip_earning','commission','incentive','payout','adjustment') NOT NULL,
  amount        DECIMAL(12,2) NOT NULL,
  balance_after DECIMAL(12,2) NOT NULL,
  ref           VARCHAR(60) NULL,
  note          VARCHAR(255) NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ledger_driver (driver_id, created_at),
  KEY idx_ledger_ride   (ride_id),
  CONSTRAINT fk_ledger_driver FOREIGN KEY (driver_id) REFERENCES rt_drivers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_payouts - withdrawal requests from wallet to the driver's bank/UPI.
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


-- =============================================================================
--  7.  RATINGS - PROMO REDEMPTIONS - SAVED PLACES - NOTIFICATIONS
-- =============================================================================

-- rt_ratings - one rating per (ride, direction). UNIQUE(ride_id, rated_by)
--   prevents a double rating. Inserting a customer->driver rating also updates
--   rt_drivers.rating_avg/rating_count in the same txn.
CREATE TABLE rt_ratings (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ride_id       BIGINT UNSIGNED NOT NULL,
  rated_by      ENUM('customer','driver') NOT NULL,
  rater_user_id BIGINT UNSIGNED NOT NULL,
  ratee_user_id BIGINT UNSIGNED NOT NULL,
  stars         TINYINT UNSIGNED NOT NULL,          -- 1..5 (checked in app)
  comment       VARCHAR(500) NULL,
  tags          JSON NULL,                          -- ['clean_car','safe_driving',...]
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_rating_ride_by (ride_id, rated_by),
  KEY idx_rating_ratee (ratee_user_id),
  CONSTRAINT fk_rating_ride FOREIGN KEY (ride_id) REFERENCES rt_rides (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_promo_redemptions - one redemption per (promo, ride). UNIQUE(promo_id,
--   ride_id) blocks re-applying the same code to one ride; the (user_id,
--   promo_id) index backs the per-user-limit check.
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
  CONSTRAINT fk_redemption_ride  FOREIGN KEY (ride_id)  REFERENCES rt_rides (id)  ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_saved_places - customer's saved locations (Home / Work / custom labels).
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

-- rt_notifications - in-app notification feed (a persisted mirror of what also
--   goes out via FCM; the DB is authoritative, push is best-effort).
CREATE TABLE rt_notifications (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  type       VARCHAR(50) NOT NULL,                  -- 'ride_assigned','driver_arrived',...
  title      VARCHAR(160) NOT NULL,
  body       VARCHAR(500) NULL,
  data       JSON NULL,
  read_at    DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notif_user (user_id, created_at),
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES rt_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
--  8.  AUTH SUPPORT  -  OTP challenges + admin audit
-- =============================================================================

-- rt_otps - OTP challenge log. `code_hash` = HMAC-SHA256(code | mobile | role,
--   server-secret) - the plaintext code is never stored. `attempts` caps
--   brute force; `consumed_at` makes each code single-use. On a new request the
--   app marks prior unconsumed codes for that (mobile, role) consumed, so only
--   the newest works. Concurrent verifies are serialised with SELECT ... FOR
--   UPDATE so a retried tap / two devices can't both succeed.
CREATE TABLE rt_otps (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mobile      VARCHAR(20) NOT NULL,
  role        ENUM('customer','driver','admin') NOT NULL,
  code_hash   CHAR(64) NOT NULL,
  expires_at  DATETIME NOT NULL,
  attempts    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  consumed_at DATETIME NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_otp_lookup  (mobile, role, consumed_at, expires_at),
  KEY idx_otp_created (created_at)                  -- retention cleanup
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- rt_admin_audit - every admin mutation (driver approval, fare change, forced
--   ride cancel, refund...) with before/after snapshots.
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
  KEY idx_audit_admin  (admin_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
--  9.  MIGRATION BOOKKEEPING (used by server/src/db/migrate.js)
-- =============================================================================
CREATE TABLE IF NOT EXISTS rt_schema_migrations (
  name       VARCHAR(255) NOT NULL,
  applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- =============================================================================
--  APPENDIX - indexes to verify with EXPLAIN before Phase 10 sign-off
-- =============================================================================
--  Q1  nearby available drivers for dispatch
--        SELECT dl.driver_id, dl.lat, dl.lng
--          FROM rt_driver_locations dl
--          JOIN rt_drivers d ON d.id = dl.driver_id
--         WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved'
--           AND dl.lat BETWEEN :latMin AND :latMax
--           AND dl.lng BETWEEN :lngMin AND :lngMax;
--        expect: idx_drivers_dispatch on rt_drivers, idx_driver_loc_box on rt_driver_locations.
--
--  Q2  customer ride history (paged)
--        SELECT ... FROM rt_rides
--         WHERE customer_id = :cid ORDER BY requested_at DESC LIMIT :n OFFSET :o;
--        expect: idx_rides_customer covers filter+sort.
--
--  Q3  driver's current active ride
--        SELECT ... FROM rt_rides WHERE driver_id = :did
--          AND status IN ('DRIVER_ASSIGNED',...,'PAYMENT_PENDING') LIMIT 1;
--        expect: idx_rides_driver.
--
--  Q4  dispatch/admin: rides waiting for a driver
--        SELECT ... FROM rt_rides WHERE status='SEARCHING_DRIVER' ORDER BY requested_at;
--        expect: idx_rides_status.
--
--  Q5  payment lookup for a ride
--        SELECT ... FROM rt_payments WHERE ride_id = :rid;
--        expect: idx_payments_ride.
--
--  Q6  driver earnings statement
--        SELECT ... FROM rt_wallet_ledger WHERE driver_id = :did
--         ORDER BY created_at DESC LIMIT :n;
--        expect: idx_ledger_driver.
--
--  Do NOT add further indexes speculatively - measure first, add to the
--  matching migration, re-EXPLAIN.
-- =============================================================================
