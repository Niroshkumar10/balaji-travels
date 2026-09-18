'use strict';

/**
 * The separate Admin Panel (ip_users/ip_roles — a different application from
 * this server, see database/bookings_admin_source.sql) assigns drivers by
 * writing rt_rides (driver_id, status) / rt_ride_status_history directly in
 * MySQL. It has no Socket.IO connection of its own, so a driver/customer app
 * sitting on the dashboard gets no real-time signal at all when the Admin
 * assigns or progresses a ride this way — confirmed by inspecting
 * rt_ride_offers (empty for these rides) and rt_ride_status_history
 * (actor: 'admin' for every step).
 *
 * Two kinds of ride land here, both handled identically from this point on:
 *   1. Bookings the Admin Panel itself created (rt_rides.booking_source =
 *      'admin_call') — always manually assigned, never auto-dispatched.
 *   2. Outstation/round_trip/rental bookings a CUSTOMER created through this
 *      app (booking_source = 'app'). rideService.createRide() deliberately
 *      never calls dispatchService.start() for these ride types (see its
 *      comment) — they sit at REQUESTED until the same external Admin Panel
 *      assigns a driver the exact same way it already does for its own
 *      call-in bookings. Local rides are never matched by the query below —
 *      they always auto-dispatch and are untouched by this job.
 *
 * This job only *notices and announces* a status this app didn't cause — it
 * does not assign drivers, does not run matching/dispatch, and does not touch
 * rt_rides itself. It reuses the exact existing 'ride:status' event (see
 * rideService.js/trackingService.js) that both the driver and customer apps
 * already treat as "something changed, re-fetch the ride" — so no client
 * change was needed to receive it.
 *
 * Status is tracked in memory only (no new column): each watched ride's
 * last-seen status is compared every tick, and a change fires one emit per
 * side. A restart re-announces whatever is currently in-flight, which is a
 * harmless no-op for a client that already has that state.
 */

const env = require('../config/env');
const logger = require('../infra/logger');
const db = require('../infra/db');
const realtime = require('../realtime/emitter');
const notifyService = require('../services/notifyService');
const userRepo = require('../repositories/userRepo');
const notificationRepo = require('../repositories/notificationRepo');
const rideRepo = require('../repositories/rideRepo');
const dispatchService = require('../services/dispatchService');
const geo = require('../services/geoService');
const { isTerminal } = require('../services/rideStateMachine');

let timer = null;
const lastStatus = new Map(); // rideId -> last-seen status string
const notifiedAssignment = new Set(); // rideIds already sent the assignment notification

async function poll() {
  if (db.MEMORY) return;
  const rows = await db.query(
    `SELECT r.id, r.status, r.customer_id, r.driver_id, r.otp,
            r.pickup_lat, r.pickup_lng, r.drop_lat, r.drop_lng, r.distance_m, r.pickup_addr,
            c.user_id AS customer_user_id, d.user_id AS driver_user_id
       FROM rt_rides r
       JOIN rt_customers c ON c.id = r.customer_id
       LEFT JOIN rt_drivers d ON d.id = r.driver_id
      WHERE (r.booking_source = 'admin_call' OR r.ride_type IN ('outstation', 'round_trip', 'rental'))
        -- Status-bound, not time-bound: an outstation/rental ride can
        -- legitimately sit REQUESTED for days waiting on a scheduled pickup
        -- or admin assignment. A rolling time window (the old
        -- "updated_at > NOW() - INTERVAL 1 DAY") would silently stop
        -- watching it before that ever happens. Terminal statuses mirror
        -- rideStateMachine.js's TERMINAL set exactly.
        AND r.status NOT IN ('COMPLETED', 'CUSTOMER_CANCELLED', 'DRIVER_CANCELLED', 'SYSTEM_CANCELLED', 'NO_DRIVERS_FOUND', 'PAYMENT_FAILED')`,
  );

  const seenIds = new Set();
  for (const row of rows) {
    seenIds.add(row.id);

    // The Admin Panel writes rt_rides directly, skipping dispatchService's
    // accept flow entirely — the ONLY place that normally generates the
    // ride-start OTP (rideRepo.setOtp, see dispatchService.js). Without this,
    // an admin-assigned ride never gets one and the driver has nothing to ask
    // the customer for. Backfill it here, the moment we see a driver on the
    // ride with no OTP yet, using the exact same generator dispatch uses.
    if (row.driver_id && !row.otp && !isTerminal(row.status)) {
      const otp = dispatchService.ride4();
      await rideRepo.setOtp(row.id, otp);
      row.otp = otp;
      logger.info({ rideId: row.id, driverId: row.driver_id }, 'admin booking: generated missing ride OTP');
    }

    // Same gap for the route: rideService.createRide() normally calls
    // geo.route() for every ride, on creation, to get the polyline the map
    // screens draw plus the real distance/duration the fare is based on. The
    // Admin Panel's direct insert only ever has pickup/drop coordinates, so
    // that never runs — the map has nothing to draw. Backfill it once,
    // keyed off distance_m (not route_polyline, which is legitimately null
    // whenever the Google Directions call falls back to a straight-line
    // estimate) so this doesn't re-call the Directions API every 4s forever.
    if (row.distance_m == null) {
      const r = await geo.route(
        { lat: Number(row.pickup_lat), lng: Number(row.pickup_lng) },
        { lat: Number(row.drop_lat), lng: Number(row.drop_lng) },
      );
      await rideRepo.setRoute(row.id, { polyline: r.polyline, distanceM: r.distanceM, durationS: r.durationS });
      row.distance_m = r.distanceM;
      logger.info({ rideId: row.id, source: r.source, distanceM: r.distanceM }, 'admin booking: generated missing route');
    }

    // Same customer + driver notification pair a normal dispatch acceptance
    // sends (see dispatchService.js's handleOfferResponse) — an admin-panel
    // booking assigns a driver directly, with no offer/accept step of its
    // own, so this is the only place either side ever hears about it.
    // Deliberately NOT gated by the status-change check below: the Admin
    // Panel routinely inserts a ride already AT 'DRIVER_ASSIGNED' on its very
    // first poll (no earlier REQUESTED state ever observed), which the
    // status-diff logic treats as "just baseline it, nothing changed" — that
    // would silently skip the one moment either side needed to hear about it.
    //
    // notifiedAssignment is only a same-process fast path — it resets on
    // every restart, and this job's `lastStatus` map is explicitly documented
    // above as fine to lose (a harmless re-announce). A lost notification
    // record is NOT harmless (a duplicate push), so the actual guard is the
    // durable check against rt_notifications itself.
    if (row.status === 'DRIVER_ASSIGNED' && row.driver_user_id && !notifiedAssignment.has(row.id)) {
      notifiedAssignment.add(row.id);
      const already = await notificationRepo.existsForRide(row.customer_user_id, 'booking_accepted', row.id);
      if (!already) {
        const driverUser = await userRepo.findById(row.driver_user_id);
        await notifyService.notify(row.customer_user_id, {
          type: 'booking_accepted',
          title: 'Your booking is accepted',
          body: 'A driver has been assigned to your ride.',
          data: { rideId: String(row.id) },
        });
        notifyService.notify(row.customer_user_id, {
          type: 'driver_assigned',
          title: 'Driver on the way',
          body: `${driverUser?.name ?? 'Your driver'} is on the way`,
          data: { rideId: String(row.id) },
        });
        notifyService.notify(row.driver_user_id, {
          type: 'ride_assigned',
          title: 'New ride assigned',
          body: `Pickup at ${row.pickup_addr ?? 'the customer’s location'}`,
          data: { rideId: String(row.id) },
        });
        logger.info(
          { rideId: row.id, customerUserId: row.customer_user_id, driverUserId: row.driver_user_id },
          'admin booking: sent assignment notifications',
        );
      }
    }

    const prev = lastStatus.get(row.id);
    if (prev === row.status) continue;
    lastStatus.set(row.id, row.status);
    if (prev === undefined) continue; // first time seeing this ride this run — nothing "changed" yet, just baseline it

    realtime.toUser(row.customer_user_id, 'ride:status', { rideId: row.id, status: row.status });
    if (row.driver_user_id) {
      realtime.toUser(row.driver_user_id, 'ride:status', { rideId: row.id, status: row.status });
    }

    logger.info(
      { rideId: row.id, status: row.status, customerUserId: row.customer_user_id, driverUserId: row.driver_user_id },
      'admin booking: announced status change',
    );
  }

  // Bound memory: forget rides no longer in the lookback window.
  for (const id of lastStatus.keys()) {
    if (!seenIds.has(id)) lastStatus.delete(id);
  }
  for (const id of notifiedAssignment) {
    if (!seenIds.has(id)) notifiedAssignment.delete(id);
  }
}

function start() {
  if (timer) return;
  timer = setInterval(() => {
    poll().catch((err) => logger.error({ err: err.message }, 'admin booking announcer tick failed'));
  }, env.ADMIN_BOOKING_POLL_MS);
  timer.unref?.();
  logger.info({ intervalMs: env.ADMIN_BOOKING_POLL_MS }, 'admin booking announcer started');
}

function stop() {
  if (timer) clearInterval(timer);
  timer = null;
  lastStatus.clear();
}

module.exports = { start, stop, poll };
