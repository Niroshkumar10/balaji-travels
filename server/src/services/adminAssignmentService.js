'use strict';

/**
 * Manual driver assignment for rental/outstation bookings.
 *
 * Local rides auto-dispatch (dispatchService.js). Rental and outstation
 * bookings skip that cascade entirely: the ride waits in
 * PENDING_ADMIN_ASSIGNMENT, an ops admin sees a ranked candidate list and
 * picks one, and the pick goes through the SAME single-offer accept/reject
 * flow a local ride's auto-dispatch uses (dispatchService.startForAdminPick)
 * — so the driver app needs no special handling for this path.
 */

const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const logger = require('../infra/logger');
const L = logger.for('dispatch');
const realtime = require('../realtime/emitter');
const rideRepo = require('../repositories/rideRepo');
const customerRepo = require('../repositories/customerRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');
const dispatchService = require('./dispatchService');
const { serviceFor } = require('../utils/serviceType');
const { windowForRideRow } = require('../utils/rideWindow');

const adminAssignmentService = {
  /** REQUESTED → PENDING_ADMIN_ASSIGNMENT, right after ride creation. */
  async queueForAdmin(ride) {
    const queued = await db.withTransaction((tx) =>
      rideRepo.transition({ rideId: ride.id, event: 'await_admin', actorRole: 'system' }, tx),
    );
    const customer = await customerRepo.findById(ride.customer_id);
    realtime.toUser(customer.user_id, 'ride:pending_admin_assignment', {
      rideId: ride.id,
      status: queued.status,
      // No real ETA model for admin response time — a static expectation is
      // honest and simple rather than inventing a prediction.
      etaHintMinutes: 30,
    });
    L.event('🗂️', 'queued for admin assignment', { rideId: ride.id, rideType: ride.ride_type });
    return queued;
  },

  /** Ranked list of eligible drivers for the ops admin to choose from. */
  async candidates(rideId) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (!['PENDING_ADMIN_ASSIGNMENT', 'SEARCHING_DRIVER'].includes(ride.status)) {
      throw ApiError.conflict(`Ride is '${ride.status}' — not awaiting admin assignment`, 'NOT_PENDING_ASSIGNMENT');
    }
    // Vehicle category is deliberately not passed as a filter — see
    // candidatesForAdmin()'s doc comment: Rental/Outstation/Round Trip
    // ignore category entirely, only Local (which never reaches this
    // function) cares about it.
    const rows = await driverLocationRepo.candidatesForAdmin({
      lat: Number(ride.pickup_lat),
      lng: Number(ride.pickup_lng),
      serviceType: serviceFor(ride.ride_type),
      newRideWindow: windowForRideRow(ride),
    });
    return rows.map((r) => ({
      driverId: r.driver_id,
      name: r.name,
      mobile: r.mobile,
      ratingAvg: Number(r.rating_avg),
      ratingCount: r.rating_count,
      vehicle: { category: r.vehicle_category, plateNo: r.plate_no, model: r.model },
      distanceM: Math.round(r.distance_m),
      currentlyOnTrip: !!r.currently_on_trip,
      lastSeenAt: r.updated_at,
    }));
  },

  /** Admin picks one candidate — hands off to the normal offer/accept flow. */
  async assign(rideId, driverId, adminId) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (ride.status !== 'PENDING_ADMIN_ASSIGNMENT') {
      throw ApiError.conflict(`Ride is '${ride.status}' — not awaiting admin assignment`, 'NOT_PENDING_ASSIGNMENT');
    }
    await db.query(
      `INSERT INTO rt_admin_audit (admin_id, action, entity, entity_id, before_val, after_val)
       VALUES (:adminId, 'ride_driver_offer', 'ride', :rideId, :before, :after)`,
      {
        adminId,
        rideId: String(rideId),
        before: JSON.stringify({ status: ride.status }),
        after: JSON.stringify({ offeredDriverId: driverId }),
      },
    );
    await dispatchService.startForAdminPick(ride, driverId);
    return rideRepo.findById(rideId);
  },
};

module.exports = adminAssignmentService;
