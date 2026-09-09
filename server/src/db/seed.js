'use strict';

/**
 * Development seed data — safe to run repeatedly (idempotent upserts).
 * Seeds: fare configs for every vehicle category + one demo promo code.
 * Does NOT seed users/drivers — those come from the OTP flow / tests.
 */

const db = require('../infra/db');
const logger = require('../infra/logger');

const FARE_CONFIGS = [
  // category,    base, incl_km, per_km, per_min, min_fare, wait/min
  ['bike', 15, 1.0, 6, 0.5, 25, 0.5],
  ['auto', 25, 1.5, 11, 1.0, 35, 1.0],
  ['hatchback', 40, 2.0, 14, 1.5, 60, 1.5],
  ['sedan', 55, 2.0, 18, 2.0, 90, 2.0],
  ['suv', 80, 2.0, 24, 2.5, 130, 2.5],
];

async function seed() {
  for (const [category, base, incl, perKm, perMin, minFare, wait] of FARE_CONFIGS) {
    await db.query(
      `INSERT INTO rt_fare_configs
         (vehicle_category, zone, base_fare, included_km, per_km, per_min,
          min_fare, waiting_per_min, free_waiting_min, surge_multiplier,
          night_multiplier, night_start, night_end, cancellation_fee, is_active)
       VALUES (:category, 'default', :base, :incl, :perKm, :perMin,
               :minFare, :wait, 3, 1.00, 1.25, '23:00:00', '05:00:00', 20, 1)
       ON DUPLICATE KEY UPDATE
         base_fare = VALUES(base_fare), included_km = VALUES(included_km),
         per_km = VALUES(per_km), per_min = VALUES(per_min),
         min_fare = VALUES(min_fare), waiting_per_min = VALUES(waiting_per_min),
         updated_at = NOW()`,
      { category, base, incl, perKm, perMin, minFare, wait },
    );
  }
  logger.info(`seeded ${FARE_CONFIGS.length} fare configs`);

  await db.query(
    `INSERT INTO rt_promos (code, description, type, value, max_discount, min_fare, per_user_limit, is_active)
     VALUES ('WELCOME50', '50% off your first ride (max ₹75)', 'percent', 50, 75, 50, 1, 1)
     ON DUPLICATE KEY UPDATE description = VALUES(description), is_active = 1`,
  );
  logger.info('seeded demo promo WELCOME50');

  await db.close();
}

seed().catch((err) => {
  logger.error({ err }, 'seed failed');
  process.exit(1);
});
