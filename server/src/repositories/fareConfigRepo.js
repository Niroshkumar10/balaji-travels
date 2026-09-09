'use strict';

const db = require('../infra/db');

/**
 * Fare configuration is a small, slow-changing reference table — SQL-only
 * (the in-memory driver is auth/profile scope only). A tiny process cache
 * avoids a query on every estimate; it's cleared on any write.
 */

let cache = null;
let cachedAt = 0;
const TTL_MS = 60_000;

const fareConfigRepo = {
  async all(ctx = db) {
    if (cache && Date.now() - cachedAt < TTL_MS) return cache;
    const rows = await ctx.query(
      `SELECT * FROM rt_fare_configs WHERE is_active = 1 ORDER BY vehicle_category, zone`,
    );
    cache = rows;
    cachedAt = Date.now();
    return rows;
  },

  async forCategory(category, zone = 'default', ctx = db) {
    const rows = await this.all(ctx);
    return (
      rows.find((r) => r.vehicle_category === category && r.zone === zone) ??
      rows.find((r) => r.vehicle_category === category && r.zone === 'default') ??
      null
    );
  },

  async findById(id, ctx = db) {
    return ctx.queryOne(`SELECT * FROM rt_fare_configs WHERE id = :id LIMIT 1`, { id });
  },

  async upsert(row, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_fare_configs
         (vehicle_category, zone, base_fare, included_km, per_km, per_min, min_fare,
          waiting_per_min, free_waiting_min, surge_multiplier, night_multiplier,
          night_start, night_end, cancellation_fee, is_active)
       VALUES
         (:vehicleCategory, :zone, :baseFare, :includedKm, :perKm, :perMin, :minFare,
          :waitingPerMin, :freeWaitingMin, :surgeMultiplier, :nightMultiplier,
          :nightStart, :nightEnd, :cancellationFee, 1)
       ON DUPLICATE KEY UPDATE
         base_fare = VALUES(base_fare), included_km = VALUES(included_km),
         per_km = VALUES(per_km), per_min = VALUES(per_min), min_fare = VALUES(min_fare),
         waiting_per_min = VALUES(waiting_per_min), free_waiting_min = VALUES(free_waiting_min),
         surge_multiplier = VALUES(surge_multiplier), night_multiplier = VALUES(night_multiplier),
         night_start = VALUES(night_start), night_end = VALUES(night_end),
         cancellation_fee = VALUES(cancellation_fee), updated_at = NOW()`,
      row,
    );
    this.clearCache();
    return res.insertId || null;
  },

  clearCache() {
    cache = null;
    cachedAt = 0;
  },
};

module.exports = fareConfigRepo;
