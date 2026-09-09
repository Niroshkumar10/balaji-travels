'use strict';

/**
 * Marks drivers offline when their heartbeat has gone stale — a backstop for
 * abrupt disconnects (app killed, network dropped) that never sent an explicit
 * driver:offline. Deliberately leaves 'on_trip' drivers alone: a driver mid-ride
 * with no signal inside a building is still on that ride.
 */

const env = require('../config/env');
const logger = require('../infra/logger');
const db = require('../infra/db');

let timer = null;

async function sweep() {
  if (db.MEMORY) return;
  try {
    const res = await db.query(
      `UPDATE rt_drivers
          SET is_online = 0, availability = 'offline'
        WHERE is_online = 1
          AND availability <> 'on_trip'
          AND (last_seen_at IS NULL OR last_seen_at < (NOW() - INTERVAL :sec SECOND))`,
      { sec: env.DRIVER_OFFLINE_SWEEP_SECONDS },
    );
    if (res.affectedRows > 0) {
      logger.info({ count: res.affectedRows }, 'offline sweep: drivers marked offline');
    }
  } catch (err) {
    logger.error({ err: err.message }, 'offline sweep failed');
  }
}

function start() {
  if (timer) return;
  const intervalMs = Math.max(15_000, (env.DRIVER_OFFLINE_SWEEP_SECONDS / 2) * 1000);
  timer = setInterval(() => {
    sweep().catch((err) => logger.error({ err }, 'offline sweep tick'));
  }, intervalMs);
  timer.unref?.();
  logger.info({ intervalMs }, 'offline sweep job started');
}

function stop() {
  if (timer) clearInterval(timer);
  timer = null;
}

module.exports = { start, stop, sweep };
