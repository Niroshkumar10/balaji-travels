'use strict';

/**
 * The accept/decline gate for admin-assigned Rental/Outstation/Round Trip
 * bookings. Sits UNDERNEATH whichever ADMIN_ASSIGNMENT_MODE actually
 * assigned the driver (env.js) rather than replacing either path:
 *
 *   - 'external_panel' (the live default): the external Admin Panel writes
 *     rt_rides.driver_id/status directly, with no accept/decline concept of
 *     its own — jobs/adminBookingAnnouncer.js is the entry point that calls
 *     announceAssignment() here instead of treating that write as final.
 *   - 'in_app': dispatchService.handleOfferResponse()'s accept path already
 *     IS the driver's explicit confirmation (a real accept/decline offer),
 *     so it calls markAcceptedFromOffer() below directly — no second gate.
 *
 * A ride can have driver_id set and status='DRIVER_ASSIGNED' at the DB
 * level while still being "not yet accepted" from this feature's point of
 * view, until driver_accepted_at/driver_accepted_by (migration 0004) are
 * set. Local rides never touch this file at all.
 */

const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const logger = require('../infra/logger');
const L = logger.for('dispatch');
const env = require('../config/env');
const realtime = require('../realtime/emitter');
const notifyService = require('./notifyService');
const notificationRepo = require('../repositories/notificationRepo');
const rideRepo = require('../repositories/rideRepo');
const rideOfferRepo = require('../repositories/rideOfferRepo');
const driverRepo = require('../repositories/driverRepo');
const customerRepo = require('../repositories/customerRepo');
const userRepo = require('../repositories/userRepo');
const vehicleRepo = require('../repositories/vehicleRepo');
const { parseDbTimestampUtc } = require('../utils/rideWindow');
const { serviceFor } = require('../utils/serviceType');
const { windowForRideRow } = require('../utils/rideWindow');

const isNonLocal = (ride) => serviceFor(ride.ride_type) !== 'local';
const isAccepted = (ride) =>
  isNonLocal(ride) && !!ride.driver_accepted_at && ride.driver_accepted_by === ride.driver_id;
/** Assigned, but still waiting on the driver to explicitly confirm. */
const isGatePending = (ride) => isNonLocal(ride) && ride.status === 'DRIVER_ASSIGNED' && !isAccepted(ride);

const maskPhone = (m) => (m ? `${m.slice(0, 2)}xxxxx${m.slice(-3)}` : null);

function assertAssignable(ride, driverProfileId) {
  if (!ride) throw ApiError.notFound('Ride not found');
  if (ride.driver_id !== driverProfileId) throw ApiError.forbidden('Not your assignment', 'RIDE_FORBIDDEN');
  if (!isNonLocal(ride)) throw ApiError.conflict('Local rides do not use this endpoint', 'NOT_AN_ASSIGNMENT');
  if (ride.status !== 'DRIVER_ASSIGNED') {
    throw ApiError.conflict(`Ride is '${ride.status}' — not awaiting acceptance`, 'NOT_PENDING_ACCEPTANCE');
  }
}

const assignmentGateService = {
  isGatePending,
  isAccepted,

  /**
   * Driver explicitly confirms an admin-assigned Rental/Trip they were just
   * notified about (external_panel path — see adminBookingAnnouncer.js).
   */
  async accept(rideId, driverProfileId) {
    const ride = await db.withTransaction(async (tx) => {
      // Serializes concurrent accepts by the same driver (and races with
      // atomicAssign's own driver-row claim) — the mutex assertNoHoldConflict
      // needs to be meaningful under concurrency.
      await tx.query('SELECT id FROM rt_drivers WHERE id = :id FOR UPDATE', { id: driverProfileId });
      const r = await rideRepo.findById(rideId, tx);
      assertAssignable(r, driverProfileId);
      if (isAccepted(r)) return r; // idempotent re-tap

      await rideRepo.assertNoHoldConflict(
        { driverId: driverProfileId, window: windowForRideRow(r), excludeRideId: rideId },
        tx,
      );
      await rideRepo.markDriverAccepted(rideId, driverProfileId, tx);
      await driverRepo.recomputeAvailability(driverProfileId, tx);
      await rideOfferRepo.create({ rideId, driverId: driverProfileId }, tx);
      await rideOfferRepo.markResponded(rideId, driverProfileId, 'accepted', tx);
      return rideRepo.findById(rideId, tx);
    });

    await this.announceAcceptance(ride);
    L.event('✅', 'driver accepted a Rental/Trip assignment', { rideId, driverId: driverProfileId });
    return ride;
  },

  /**
   * Driver explicitly declines — the booking goes back to wherever it was
   * before this admin pick (never a terminal/failed status), for someone
   * else to be assigned. Mode-aware: which status it returns to depends on
   * which admin-assignment mode is live (only one ever is at a time).
   */
  async decline(rideId, driverProfileId, reason) {
    const { ride, event } = await db.withTransaction(async (tx) => {
      await tx.query('SELECT id FROM rt_drivers WHERE id = :id FOR UPDATE', { id: driverProfileId });
      const r = await rideRepo.findById(rideId, tx);
      assertAssignable(r, driverProfileId);

      await rideOfferRepo.create({ rideId, driverId: driverProfileId }, tx);
      await rideOfferRepo.markResponded(rideId, driverProfileId, 'rejected', tx);
      await rideRepo.clearAssignment(rideId, tx);
      const ev = env.ADMIN_ASSIGNMENT_MODE === 'in_app' ? 'decline_assignment_admin' : 'decline_assignment_panel';
      const updated = await rideRepo.transition(
        { rideId, event: ev, actorRole: 'driver', actorId: driverProfileId, meta: { reason: reason ?? null } },
        tx,
      );
      await driverRepo.recomputeAvailability(driverProfileId, tx);
      return { ride: updated, event: ev };
    });

    const customer = await customerRepo.findById(ride.customer_id);
    realtime.toUser(customer.user_id, 'ride:status', { rideId, status: ride.status });
    await notifyService.notify(customer.user_id, {
      type: 'assignment_pending',
      title: 'Finding your driver',
      body: 'The previously assigned driver is unavailable — we’re assigning someone else.',
      data: { rideId: String(rideId) },
    });
    L.event('❌', 'driver declined a Rental/Trip assignment', { rideId, driverId: driverProfileId, event, reason });
    return ride;
  },

  /**
   * The 'in_app' mode bridge: dispatchService.handleOfferResponse()'s
   * accept path already represents an explicit driver confirmation (a real
   * accept/decline offer, not a bare DB write) — this just records that
   * acceptance through the same gate columns/derivation everything else
   * uses, inside the SAME transaction as the ride claim. Throws
   * RESERVATION_TIME_CONFLICT (rolling back the whole accept) if this
   * booking overlaps something the driver already holds.
   */
  async markAcceptedFromOffer(rideId, driverId, tx) {
    const ride = await rideRepo.findById(rideId, tx);
    await rideRepo.assertNoHoldConflict(
      { driverId, window: windowForRideRow(ride), excludeRideId: rideId },
      tx,
    );
    await rideRepo.markDriverAccepted(rideId, driverId, tx);
    await driverRepo.recomputeAvailability(driverId, tx);
  },

  /**
   * The new, calm "Rental Trip Assigned" notification — replaces the
   * existing ride_assigned/booking_accepted/driver_assigned trio for a
   * non-local ride until the driver actually accepts. One function serves
   * both admin-assignment modes (called from adminBookingAnnouncer.js for
   * external_panel, and — for in_app, which satisfies the gate immediately
   * on offer-accept — announceAcceptance() below is used instead, since
   * there's nothing left to separately "await" in that mode).
   */
  async announceAssignment(ride) {
    if (!ride.driver_id) return;
    const driver = await driverRepo.findById(ride.driver_id, db);
    if (!driver) return;
    // Keyed by driver's userId (not just rideId), so a reassignment to a
    // DIFFERENT driver (the panel re-pointing driver_id) still notifies the
    // new one even though this rideId was already notified once before.
    const already = await notificationRepo.existsForRide(driver.user_id, 'rental_trip_assigned', ride.id);
    if (already) return;

    const kind = serviceFor(ride.ride_type) === 'rental' ? 'Rental' : 'Outstation';
    const when = ride.scheduled_at ? parseDbTimestampUtc(ride.scheduled_at).toISOString() : null;
    await notifyService.notify(driver.user_id, {
      type: 'rental_trip_assigned',
      title: `${kind} Trip Assigned`,
      body: `You're assigned for a ${kind.toLowerCase()} trip${when ? ' — review and confirm.' : '.'}`,
      // Custom socket event (notifyService defaults to generic 'notification')
      // — lets RentalTripController (Flutter) refresh specifically on this,
      // without depending on the unrelated ride:status/ride:assigned events.
      socketEvent: 'ride:assignment_pending',
      data: {
        rideId: String(ride.id),
        rideType: ride.ride_type,
        scheduledAt: when ?? '',
        pickupAddr: ride.pickup_addr ?? '',
      },
    });
  },

  /** Customer's existing "driver assigned" pair, moved to acceptance-time for non-local rides. */
  async announceAcceptance(ride) {
    const [customer, driver] = await Promise.all([
      customerRepo.findById(ride.customer_id),
      driverRepo.findById(ride.driver_id),
    ]);
    if (!customer || !driver) return;
    const [driverUser, vehicle] = await Promise.all([
      userRepo.findById(driver.user_id),
      driver.current_vehicle_id ? vehicleRepo.findById(driver.current_vehicle_id) : null,
    ]);

    realtime.toUser(customer.user_id, 'ride:driver_assigned', {
      rideId: ride.id,
      status: ride.status,
      otp: ride.otp,
      driver: {
        id: driver.id,
        name: driverUser?.name ?? 'Driver',
        rating: Number(driver.rating_avg),
        phoneMasked: maskPhone(driverUser?.mobile),
      },
      vehicle: vehicle
        ? { category: vehicle.category, plateNo: vehicle.plate_no, make: vehicle.make, model: vehicle.model, color: vehicle.color }
        : null,
    });
    await notifyService.notify(customer.user_id, {
      type: 'booking_accepted',
      title: 'Your booking is accepted',
      body: 'A driver has accepted your ride.',
      data: { rideId: String(ride.id) },
    });
    await notifyService.notify(customer.user_id, {
      type: 'driver_assigned',
      title: 'Driver assigned',
      body: `${driverUser?.name ?? 'Your driver'} · ${vehicle?.plate_no ?? ''}`.trim(),
      data: { rideId: String(ride.id) },
    });
  },
};

module.exports = assignmentGateService;
