'use strict';

/**
 * The separate Admin Panel (ip_users/ip_roles — a different application from
 * this server, see database/bookings_admin_source.sql) creates and progresses
 * "call-in" bookings (rt_rides.booking_source = 'admin_call') by writing
 * rt_rides / rt_ride_status_history directly in MySQL. It has no Socket.IO
 * connection of its own, so a driver/customer app sitting on the dashboard
 * gets no real-time signal at all when the Admin assigns or progresses one of
 * these rides — confirmed by inspecting rt_ride_offers (empty for these rides)
 * and rt_ride_status_history (actor: 'admin' for every step).
 *
 * This job only *notices and announces* a status this app didn't cause — it
 * does not assign drivers, does not run matching/dispatch, and does not touch
 * rt_rides itself. It reuses the exact existing 'ride:status' event (see
 * rideService.js/trackingService.js) that both the driver and customer apps
 * already treat as "something changed, re-fetch the ride" — so no client
 * change was needed to receive it.
 *
 * Status is tracked in memory only (no new column): each admin_call ride's
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

let timer = null;
const lastStatus = new Map(); // rideId -> last-seen status string

async function poll() {
  if (db.MEMORY) return;
  const rows = await db.query(
    `SELECT r.id, r.status, r.customer_id, r.driver_id,
            c.user_id AS customer_user_id, d.user_id AS driver_user_id
       FROM rt_rides r
       JOIN rt_customers c ON c.id = r.customer_id
       LEFT JOIN rt_drivers d ON d.id = r.driver_id
      WHERE r.booking_source = 'admin_call'
        AND r.updated_at > (NOW() - INTERVAL 1 DAY)`,
  );

  const seenIds = new Set();
  for (const row of rows) {
    seenIds.add(row.id);
    const prev = lastStatus.get(row.id);
    if (prev === row.status) continue;
    lastStatus.set(row.id, row.status);
    if (prev === undefined) continue; // first time seeing this ride this run — nothing "changed" yet, just baseline it

    realtime.toUser(row.customer_user_id, 'ride:status', { rideId: row.id, status: row.status });
    if (row.driver_user_id) {
      realtime.toUser(row.driver_user_id, 'ride:status', { rideId: row.id, status: row.status });
    }

    // Same customer-facing "Driver on the way" notify() dispatchService sends
    // for a normal assignment — writes the durable rt_notifications row too,
    // so it shows in the customer's Notifications tab, not just live sockets.
    if (row.status === 'DRIVER_ASSIGNED' && row.driver_user_id) {
      const driverUser = await userRepo.findById(row.driver_user_id);
      notifyService.notify(row.customer_user_id, {
        type: 'driver_assigned',
        title: 'Driver on the way',
        body: `${driverUser?.name ?? 'Your driver'} is on the way`,
        data: { rideId: String(row.id) },
      });
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
