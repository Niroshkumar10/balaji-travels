'use strict';

const db = require('../infra/db');

const ratingRepo = {
  async create({ rideId, ratedBy, raterUserId, rateeUserId, stars, comment, tags }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_ratings (ride_id, rated_by, rater_user_id, ratee_user_id, stars, comment, tags)
       VALUES (:rideId, :ratedBy, :raterUserId, :rateeUserId, :stars, :comment, :tags)`,
      {
        rideId,
        ratedBy,
        raterUserId,
        rateeUserId,
        stars,
        comment: comment ?? null,
        tags: tags ? JSON.stringify(tags) : null,
      },
    );
    return res.insertId;
  },

  forRide(rideId, ctx = db) {
    return ctx.query(
      `SELECT rated_by, stars, comment, tags, created_at FROM rt_ratings WHERE ride_id = :rideId`,
      { rideId },
    );
  },

  /** Recompute a driver's aggregate from customer→driver ratings. */
  driverStats(driverId, ctx = db) {
    return ctx.queryOne(
      `SELECT ROUND(AVG(r.stars), 2) AS avg, COUNT(*) AS count
         FROM rt_ratings r
         JOIN rt_rides rd ON rd.id = r.ride_id
        WHERE rd.driver_id = :driverId AND r.rated_by = 'customer'`,
      { driverId },
    );
  },
};

module.exports = ratingRepo;
