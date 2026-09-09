'use strict';

const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const ratingRepo = require('../repositories/ratingRepo');
const rideRepo = require('../repositories/rideRepo');
const driverRepo = require('../repositories/driverRepo');
const customerRepo = require('../repositories/customerRepo');

const ratingService = {
  /**
   * @param {number} rideId
   * @param {object} p
   * @param {'customer'|'driver'} p.byRole
   * @param {number} p.raterUserId
   * @param {number} p.raterProfileId  rt_customers.id or rt_drivers.id
   * @param {number} p.stars 1..5
   */
  async rate(rideId, { byRole, raterUserId, raterProfileId, stars, comment, tags }) {
    if (!(stars >= 1 && stars <= 5)) throw ApiError.badRequest('stars must be 1..5', 'BAD_STARS');

    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (ride.status !== 'COMPLETED') {
      throw ApiError.badRequest('You can only rate a completed ride', 'RIDE_NOT_COMPLETED');
    }
    if (byRole === 'customer' && ride.customer_id !== raterProfileId) throw ApiError.forbidden();
    if (byRole === 'driver' && ride.driver_id !== raterProfileId) throw ApiError.forbidden();
    if (byRole === 'driver' && !ride.driver_id) throw ApiError.badRequest('No driver on this ride');

    const driver = ride.driver_id ? await driverRepo.findById(ride.driver_id) : null;
    const customer = await customerRepo.findById(ride.customer_id);
    const rateeUserId = byRole === 'customer' ? driver?.user_id : customer?.user_id;
    if (!rateeUserId) throw ApiError.badRequest('Nobody to rate on this ride');

    try {
      await db.withTransaction(async (tx) => {
        await ratingRepo.create(
          { rideId, ratedBy: byRole, raterUserId, rateeUserId, stars, comment, tags },
          tx,
        );
        if (byRole === 'customer' && ride.driver_id) {
          const s = await ratingRepo.driverStats(ride.driver_id, tx);
          await driverRepo.updateRating(
            ride.driver_id,
            { avg: Number(s.avg ?? stars), count: Number(s.count ?? 1) },
            tx,
          );
        }
      });
    } catch (err) {
      if (err.code === 'ER_DUP_ENTRY') {
        throw ApiError.conflict('You have already rated this ride', 'ALREADY_RATED');
      }
      throw err;
    }
    return { ok: true };
  },

  forRide(rideId) {
    return ratingRepo.forRide(rideId);
  },
};

module.exports = ratingService;
