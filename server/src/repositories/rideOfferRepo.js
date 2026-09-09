'use strict';

const db = require('../infra/db');

const rideOfferRepo = {
  async create({ rideId, driverId, distanceM }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_ride_offers (ride_id, driver_id, status, distance_m)
       VALUES (:rideId, :driverId, 'sent', :distanceM)
       ON DUPLICATE KEY UPDATE status = 'sent', distance_m = VALUES(distance_m),
                               sent_at = NOW(), responded_at = NULL`,
      { rideId, driverId, distanceM: distanceM ?? null },
    );
    return res.insertId;
  },

  async markResponded(rideId, driverId, status, ctx = db) {
    await ctx.query(
      `UPDATE rt_ride_offers SET status = :status, responded_at = NOW()
        WHERE ride_id = :rideId AND driver_id = :driverId`,
      { rideId, driverId, status },
    );
  },

  async supersedeOthers(rideId, keepDriverId, ctx = db) {
    await ctx.query(
      `UPDATE rt_ride_offers SET status = 'superseded', responded_at = NOW()
        WHERE ride_id = :rideId AND driver_id <> :keepDriverId AND status = 'sent'`,
      { rideId, keepDriverId },
    );
  },

  async timeoutAllSent(rideId, ctx = db) {
    await ctx.query(
      `UPDATE rt_ride_offers SET status = 'timed_out', responded_at = NOW()
        WHERE ride_id = :rideId AND status = 'sent'`,
      { rideId },
    );
  },

  async offeredDriverIds(rideId, ctx = db) {
    const rows = await ctx.query(
      `SELECT driver_id FROM rt_ride_offers WHERE ride_id = :rideId`,
      { rideId },
    );
    return rows.map((r) => r.driver_id);
  },

  async getOffer(rideId, driverId, ctx = db) {
    return ctx.queryOne(
      `SELECT * FROM rt_ride_offers WHERE ride_id = :rideId AND driver_id = :driverId LIMIT 1`,
      { rideId, driverId },
    );
  },
};

module.exports = rideOfferRepo;
