'use strict';

const db = require('../infra/db');
const env = require('../config/env');
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
   * Online + available + KYC-approved drivers of the right vehicle category,
   * nearest first. `radiusKm` limits how far a driver may be from (lat,lng);
   * pass 0 / null / Infinity for NO distance limit (used by dispatch's
   * queue-exhaustion re-query — take any online driver, closest first).
   * Coarse bounding-box in SQL, exact Haversine sort in JS.
   */
  async nearby(
    {
      lat,
      lng,
      radiusKm,
      categories,
      staleSeconds = env.DRIVER_LOCATION_STALE_SECONDS,
      limit = 20,
    },
    ctx = db,
  ) {
    const limited = Number.isFinite(radiusKm) && radiusKm > 0;
    const catFilter =
      Array.isArray(categories) && categories.length
        ? `AND v.category IN (${categories.map((_, i) => `:cat${i}`).join(',')})`
        : '';
    const params = { staleSeconds };
    (categories ?? []).forEach((c, i) => {
      params[`cat${i}`] = c;
    });

    let boxFilter = '';
    if (limited) {
      const box = boundingBox(lat, lng, radiusKm);
      boxFilter =
        'AND dl.lat BETWEEN :latMin AND :latMax AND dl.lng BETWEEN :lngMin AND :lngMax';
      Object.assign(params, {
        latMin: box.latMin,
        latMax: box.latMax,
        lngMin: box.lngMin,
        lngMax: box.lngMax,
      });
    }

    // INNER JOIN, fully validated: the driver's category comes ONLY from the
    // vehicle that current_vehicle_id points at, and only when that vehicle is
    // active, not soft-deleted, and actually belongs to this driver. A driver
    // without such a pairing can never be dispatched, so they must not appear.
    const rows = await ctx.query(
      `SELECT d.id AS driver_id, d.rating_avg, d.current_vehicle_id,
              v.id AS vehicle_id, v.category AS vehicle_category, v.plate_no,
              dl.lat, dl.lng, dl.bearing, dl.updated_at
         FROM rt_driver_locations dl
         JOIN rt_drivers d  ON d.id = dl.driver_id
         JOIN rt_vehicles v ON v.id = d.current_vehicle_id
                           AND v.driver_id = d.id
                           AND v.is_active = 1
                           AND v.deleted_at IS NULL
        WHERE d.is_online = 1
          AND d.availability = 'available'
          AND d.kyc_status = 'approved'
          AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)
          ${boxFilter}
          ${catFilter}`,
      params,
    );

    return rows
      .map((r) => ({
        ...r,
        distance_m: haversineMeters(lat, lng, Number(r.lat), Number(r.lng)),
      }))
      .filter((r) => !limited || r.distance_m <= radiusKm * 1000)
      .sort((a, b) => a.distance_m - b.distance_m)
      .slice(0, limit);
  },

  /**
   * Why is `nearby` returning nothing? Counts drivers surviving each filter
   * stage so a "no drivers found" can name the exact cause in the logs.
   */
  async diagnose({ lat, lng, radiusKm, category, staleSeconds = env.DRIVER_LOCATION_STALE_SECONDS }, ctx = db) {
    const limited = Number.isFinite(radiusKm) && radiusKm > 0;
    const box = limited
      ? boundingBox(lat, lng, radiusKm)
      : { latMin: -90, latMax: 90, lngMin: -180, lngMax: 180 };
    const row = await ctx.queryOne(
      `SELECT
         (SELECT COUNT(*) FROM rt_drivers WHERE is_online = 1) AS online,
         (SELECT COUNT(*) FROM rt_drivers WHERE is_online = 1 AND availability = 'available') AS available,
         (SELECT COUNT(*) FROM rt_drivers WHERE is_online = 1 AND availability = 'available' AND kyc_status = 'approved') AS kyc_ok,
         (SELECT COUNT(*)
            FROM rt_drivers d JOIN rt_driver_locations dl ON dl.driver_id = d.id
           WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved') AS has_location,
         (SELECT COUNT(*)
            FROM rt_drivers d JOIN rt_driver_locations dl ON dl.driver_id = d.id
           WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved'
             AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)) AS fresh_location,
         (SELECT COUNT(*)
            FROM rt_drivers d JOIN rt_driver_locations dl ON dl.driver_id = d.id
           WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved'
             AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)
             AND dl.lat BETWEEN :latMin AND :latMax AND dl.lng BETWEEN :lngMin AND :lngMax) AS in_box,
         (SELECT COUNT(*)
            FROM rt_drivers d
            JOIN rt_driver_locations dl ON dl.driver_id = d.id
            JOIN rt_vehicles v ON v.id = d.current_vehicle_id
                              AND v.driver_id = d.id
                              AND v.is_active = 1
                              AND v.deleted_at IS NULL
           WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved'
             AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)
             AND dl.lat BETWEEN :latMin AND :latMax AND dl.lng BETWEEN :lngMin AND :lngMax
             AND v.category = :category) AS category_match`,
      {
        staleSeconds,
        latMin: box.latMin,
        latMax: box.latMax,
        lngMin: box.lngMin,
        lngMax: box.lngMax,
        category,
      },
    );

    // Per-driver vehicle breakdown for the online pool, so the log can name
    // exactly why each driver was (or wasn't) a category match. LEFT JOIN on
    // purpose: we still want to SEE a driver whose current_vehicle_id doesn't
    // resolve to a valid active owned vehicle.
    const drivers = await ctx.query(
      `SELECT d.id AS driver_id,
              d.current_vehicle_id,
              v.id       AS active_vehicle_id,
              v.category AS vehicle_category,
              v.is_active,
              (v.id IS NOT NULL AND v.category = :category) AS category_ok
         FROM rt_drivers d
         JOIN rt_driver_locations dl ON dl.driver_id = d.id
         LEFT JOIN rt_vehicles v ON v.id = d.current_vehicle_id
                               AND v.driver_id = d.id
                               AND v.is_active = 1
                               AND v.deleted_at IS NULL
        WHERE d.is_online = 1 AND d.availability = 'available' AND d.kyc_status = 'approved'
          AND dl.updated_at >= (NOW() - INTERVAL :staleSeconds SECOND)
        ORDER BY d.id
        LIMIT 20`,
      { staleSeconds, category },
    );

    return {
      online: Number(row?.online ?? 0),
      available: Number(row?.available ?? 0),
      kycApproved: Number(row?.kyc_ok ?? 0),
      hasLocationRow: Number(row?.has_location ?? 0),
      freshLocation: Number(row?.fresh_location ?? 0),
      insideRadiusBox: Number(row?.in_box ?? 0),
      categoryMatch: Number(row?.category_match ?? 0),
      staleSeconds,
      radiusKm: limited ? radiusKm : null, // null → no distance limit
      category,
      requestedCategory: category,
      drivers: (drivers ?? []).map((r) => ({
        driverId: r.driver_id,
        currentVehicleId: r.current_vehicle_id ?? null,
        activeVehicleId: r.active_vehicle_id ?? null,
        vehicleCategory: r.vehicle_category ?? null,
        isActive: r.is_active == null ? null : Number(r.is_active),
        categoryOk: !!Number(r.category_ok),
      })),
    };
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
