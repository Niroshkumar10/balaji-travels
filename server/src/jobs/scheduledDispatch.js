'use strict';

/**
 * Real scheduled dispatch — a LOCAL ride booked for a future date/time (see
 * rideService.createRide()'s `scheduledAt` handling) sits at REQUESTED with
 * dispatch deliberately not started yet. This job is the other half: once a
 * scheduled ride's time is close, it calls the EXACT SAME
 * dispatchService.start() every normal ride uses — no second dispatch/offer
 * engine, this only decides *when* to call the one that already exists.
 *
 * Scoped to ride_type='local' only. A scheduled outstation/round_trip/rental
 * ride also sits at REQUESTED, but on purpose stays there forever (or until
 * the external Admin Panel assigns a driver) — its scheduled time arriving
 * is not a signal to auto-dispatch it; see rideService.createRide() and
 * adminBookingAnnouncer.js.
 */

const env = require('../config/env');
const logger = require('../infra/logger');
const db = require('../infra/db');
const rideRepo = require('../repositories/rideRepo');
const dispatchService = require('../services/dispatchService');

let timer = null;
const started = new Set(); // rideId -> already handed to dispatchService this run, avoids a double-start if a poll tick overlaps a slow dispatch.start()

async function poll() {
  if (db.MEMORY) return;
  const rows = await db.query(
    `SELECT id FROM rt_rides
      WHERE status = 'REQUESTED'
        AND ride_type = 'local'
        AND scheduled_at IS NOT NULL
        AND scheduled_at <= NOW()
      ORDER BY scheduled_at ASC
      LIMIT 20`,
  );

  for (const row of rows) {
    if (started.has(row.id)) continue;
    started.add(row.id);
    try {
      const ride = await rideRepo.findById(row.id);
      // Re-check status — the ride may have been cancelled between the query
      // above and now; dispatchService.start() has no idea what a cancelled
      // ride is and would just churn through "no drivers" for it.
      if (!ride || ride.status !== 'REQUESTED') continue;
      logger.info({ rideId: ride.id, scheduledAt: ride.scheduled_at }, 'scheduled ride: starting dispatch');
      await dispatchService.start(ride);
    } catch (err) {
      logger.error({ err: err.message, rideId: row.id }, 'scheduled dispatch failed');
    } finally {
      started.delete(row.id);
    }
  }
}

function start() {
  if (timer) return;
  timer = setInterval(() => {
    poll().catch((err) => logger.error({ err: err.message }, 'scheduled dispatch tick failed'));
  }, env.SCHEDULED_DISPATCH_POLL_MS);
  timer.unref?.();
  logger.info({ intervalMs: env.SCHEDULED_DISPATCH_POLL_MS }, 'scheduled dispatch job started');
}

function stop() {
  if (timer) clearInterval(timer);
  timer = null;
  started.clear();
}

module.exports = { start, stop, poll };
