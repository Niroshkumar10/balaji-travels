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

  /**
   * Publishes a new active fare version for (vehicle_category, zone).
   *
   * `effective_from` is part of the table's unique key precisely so each
   * change can be kept as its own row (real version history) instead of a
   * value silently overwritten in place — but that only works if publishing
   * a new version also retires the old one. Previously this ran a bare
   * INSERT ... ON DUPLICATE KEY UPDATE, and because effective_from defaults
   * to NOW() on every call, no two calls ever shared a key: every "update"
   * actually inserted a brand new is_active=1 row alongside the old one.
   * forCategory()'s `rows.find(...)` then always returned whichever row
   * happened to sort first — the ORIGINAL config — so admin fare changes
   * were silently never applied. Fixed by explicitly deactivating the
   * current active row for that category/zone before inserting the new one,
   * inside one transaction, so exactly one row is ever active at a time.
   */
  async upsert(row, ctx = db) {
    const run = async (tx) => {
      await tx.query(
        `UPDATE rt_fare_configs SET is_active = 0, updated_at = NOW()
          WHERE vehicle_category = :vehicleCategory AND zone = :zone AND is_active = 1`,
        row,
      );
      const res = await tx.query(
        `INSERT INTO rt_fare_configs
           (vehicle_category, zone, base_fare, included_km, per_km, per_min, min_fare,
            waiting_per_min, free_waiting_min, surge_multiplier, night_multiplier,
            night_start, night_end, cancellation_fee, is_active)
         VALUES
           (:vehicleCategory, :zone, :baseFare, :includedKm, :perKm, :perMin, :minFare,
            :waitingPerMin, :freeWaitingMin, :surgeMultiplier, :nightMultiplier,
            :nightStart, :nightEnd, :cancellationFee, 1)`,
        row,
      );
      return res.insertId || null;
    };
    // Callers may already be inside a transaction (ctx is a tx context, not
    // the shared `db` module) — only open a new one when we're not.
    const id = ctx === db ? await db.withTransaction(run) : await run(ctx);
    this.clearCache();
    return id;
  },

  clearCache() {
    cache = null;
    cachedAt = 0;
  },
};

module.exports = fareConfigRepo;
