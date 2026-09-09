'use strict';

/**
 * Live GPS relay for an active ride.
 *
 *   driver GPS ─► rt_driver_locations (upsert, every ping — one cheap row)
 *              ─► customer socket  'ride:driver_location'  (+ live ETA)
 *              ─► rt_driver_location_logs  (THROTTLED: only when enough time
 *                 has passed AND the driver has moved far enough — never on
 *                 every raw tick, per the Microlab "don't write the DB on
 *                 every GPS event" lesson)
 *
 * Also promotes RIDE_STARTED → RIDE_IN_PROGRESS on the first ping after start.
 */

const env = require('../config/env');
const logger = require('../infra/logger');
const db = require('../infra/db');
const realtime = require('../realtime/emitter');
const geo = require('./geoService');
const rideRepo = require('../repositories/rideRepo');
const driverRepo = require('../repositories/driverRepo');
const customerRepo = require('../repositories/customerRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');

const DRIVE_STATES = new Set([
  'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED', 'RIDE_STARTED', 'RIDE_IN_PROGRESS',
]);

/** rideId -> { lastLogAt, lastLat, lastLng, progressed } */
const perRide = new Map();

function etaFor(ride, from) {
  const target =
    ['RIDE_STARTED', 'RIDE_IN_PROGRESS'].includes(ride.status)
      ? { lat: Number(ride.drop_lat), lng: Number(ride.drop_lng) }
      : { lat: Number(ride.pickup_lat), lng: Number(ride.pickup_lng) };
  return geo.etaSeconds(from, target);
}

const trackingService = {
  /** Called from the authenticated driver socket. */
  async relay({ driverProfileId, rideId, lat, lng, bearing, speedKmph }) {
    if (lat == null || lng == null) return;

    let ride = rideId
      ? await rideRepo.findById(rideId)
      : await rideRepo.findActiveForDriver(driverProfileId);
    if (!ride || ride.driver_id !== driverProfileId || !DRIVE_STATES.has(ride.status)) {
      // still keep last-known position current even if between rides
      await driverLocationRepo.upsert(driverProfileId, { lat, lng, bearing, speedKmph });
      return;
    }

    await driverLocationRepo.upsert(driverProfileId, { lat, lng, bearing, speedKmph });

    // promote to in-progress on first ping after start
    if (ride.status === 'RIDE_STARTED' && !perRide.get(ride.id)?.progressed) {
      try {
        const updated = await db.withTransaction((tx) =>
          rideRepo.transition({ rideId: ride.id, event: 'trip_progress', actorRole: 'system' }, tx),
        );
        ride = updated;
        const customer = await customerRepo.findById(ride.customer_id);
        realtime.toUser(customer.user_id, 'ride:status', { rideId: ride.id, status: ride.status });
      } catch (err) {
        logger.debug({ err: err.message }, 'trip_progress skipped');
      }
    }

    const etaSeconds = etaFor(ride, { lat, lng });
    const customer = await customerRepo.findById(ride.customer_id);
    realtime.toUser(customer.user_id, 'ride:driver_location', {
      rideId: ride.id,
      lat: Number(lat),
      lng: Number(lng),
      bearing: bearing ?? null,
      speedKmph: speedKmph ?? null,
      etaSeconds,
      status: ride.status,
    });

    // throttled breadcrumb
    const st = perRide.get(ride.id) ?? { lastLogAt: 0, lastLat: null, lastLng: null, progressed: false };
    if (ride.status === 'RIDE_IN_PROGRESS' || ride.status === 'RIDE_STARTED') st.progressed = true;
    const now = Date.now();
    const movedM =
      st.lastLat == null ? Infinity : geo.haversineMeters(st.lastLat, st.lastLng, lat, lng);
    if (now - st.lastLogAt >= env.TRACK_LOG_MIN_INTERVAL_MS && movedM >= env.TRACK_LOG_MIN_MOVE_M) {
      st.lastLogAt = now;
      st.lastLat = lat;
      st.lastLng = lng;
      driverLocationRepo
        .logBreadcrumb(driverProfileId, ride.id, { lat, lng, bearing, speedKmph })
        .catch((err) => logger.debug({ err: err.message }, 'breadcrumb write failed'));
    }
    perRide.set(ride.id, st);
  },

  /** Customer's location while waiting (optional — shared with the driver). */
  async customerPing({ customerProfileId, rideId, lat, lng }) {
    const ride = await rideRepo.findById(rideId);
    if (!ride || ride.customer_id !== customerProfileId || !ride.driver_id) return;
    const drv = await driverRepo.findById(ride.driver_id);
    if (drv) {
      realtime.toUser(drv.user_id, 'ride:customer_location', { rideId, lat: Number(lat), lng: Number(lng) });
    }
  },

  clearRide(rideId) {
    perRide.delete(rideId);
  },
};

module.exports = trackingService;
