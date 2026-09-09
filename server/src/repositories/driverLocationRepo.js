'use strict';

const db = require('../infra/db');
const { boundingBox, haversineMeters } = require('../services/geoService');

const driverLocationRepo = {
  /** Upsert the driver's last-known position (called on every heartbeat/ping). */
  async upsert(driverId, { lat, lng, bearing, speedKmph, accuracyM, battery }, ctx = db) {
    await ctx.query(
      `INSERT INTO rt_driver_locations
         (driver_id, lat, lng, bearing, speed_kmph, accuracy_m, battery)
       VALUES (:driverId, :lat, :lng, :bearing, :speedKmph, :accuracyM, :battery)
       ON DUPLICATE KEY UPDATE
         lat = VALUES(lat), lng = VALUES(lng), bearing = VALUES(bearing),
         speed_kmph = VALUES(speed_kmph), accuracy_m = VALUES(accuracy_m),
         battery = VALUES(battery), updated_at = NOW()`,
      {
        driverId,
        lat,
        lng,
        bearing: bearing ?? null,
        speedKmph: speedKmph ?? null,
        accuracyM: accuracyM ?? null,
        battery: battery ?? null,
      },
    );
  },

  async get(driverId, ctx = db) {
    return ctx.queryOne(`SELECT * FROM rt_driver_locations WHERE driver_id = :driverId LIMIT 1`, {
      driverId,
    });
  },

  /**
   * Online + available + KYC-approved drivers within `radiusKm` of (lat,lng),
   * optionally filtered to vehicle categories, nearest first.
   * Coarse bounding-box filter in SQL (uses idx_driver_loc_box), exact Haversine
   * sort in JS on the survivors.
   */
  async nearby({ lat, lng, radiusKm, categories, staleSeconds = 60, limit = 20 }, ctx = db) {
    const box = boundingBox(lat, lng, radiusKm);
    const catFilter =
      Array.isArray(categories) && categories.length
        ? `AND v.category IN (${categories.map((_, i) => `:cat${i}`).join(',')})`
        : '';
    const params = {
      latMin: box.latMin,
      latMax: box.latMax,
      lngMin: box.lngMin,
      lngMax: box.lngMax,
      staleSeconds,
    };
    (categories ?? []).forEach((c, i) => {
      params[`cat${i}`] = c;
    });

    const rows = await ctx.query(
      `SELECT d.id AS driver_id, d.rating_avg, d.current_vehicle_id,
              v.id AS vehicle_id, v.category AS vehicle_category, v.plate_no,
              dl.lat, dl.lng, dl.bearing, dl.updated_at
         FROM rt_driver_locations dl
         JOIN rt_drivers d  ON d.id = dl.driver_id
         LEFT JOIN rt_vehicles v ON v.id = d.current_vehicle_id AND v.is_active = 1
        WHERE d.is_online = 1
          AND d.availability = 'available'
          AND d.kyc_status = 'approved'
          AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)
          AND dl.lat BETWEEN :latMin AND :latMax
          AND dl.lng BETWEEN :lngMin AND :lngMax
          ${catFilter}`,
      params,
    );

    return rows
      .map((r) => ({
        ...r,
        distance_m: haversineMeters(lat, lng, Number(r.lat), Number(r.lng)),
      }))
      .filter((r) => r.distance_m <= radiusKm * 1000)
      .sort((a, b) => a.distance_m - b.distance_m)
      .slice(0, limit);
  },

  /** Append a throttled breadcrumb during an active ride. */
  async logBreadcrumb(driverId, rideId, { lat, lng, bearing, speedKmph }, ctx = db) {
    await ctx.query(
      `INSERT INTO rt_driver_location_logs (driver_id, ride_id, lat, lng, bearing, speed_kmph)
       VALUES (:driverId, :rideId, :lat, :lng, :bearing, :speedKmph)`,
      { driverId, rideId, lat, lng, bearing: bearing ?? null, speedKmph: speedKmph ?? null },
    );
  },

  async ridePath(rideId, ctx = db) {
    return ctx.query(
      `SELECT lat, lng, bearing, speed_kmph, recorded_at
         FROM rt_driver_location_logs WHERE ride_id = :rideId ORDER BY id ASC`,
      { rideId },
    );
  },
};

module.exports = driverLocationRepo;
