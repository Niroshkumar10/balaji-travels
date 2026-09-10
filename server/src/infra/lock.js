'use strict';

/**
 * Short-lived in-process mutex.
 *
 * RedTaxi runs as a single Node process (like Microlab did), so dispatch's
 * accept-race guard only needs a per-process lock — the real cross-caller
 * guarantee is the conditional UPDATE in `rideRepo.atomicAssign`, this just
 * makes the losing side cheap. If you ever run multiple instances, put a
 * distributed lock (Redis SET NX) back here behind the same `acquire()` API.
 */

const logger = require('./logger');

const held = new Map(); // key -> expiry epoch ms

/**
 * Acquire an exclusive lock. Returns a `release()` function, or `null` if the
 * key is already locked.
 *
 * @param {string} key
 * @param {number} ttlMs  auto-expiry so a crash can't wedge the key forever
 * @returns {Promise<null | (() => Promise<void>)>}
 */
async function acquire(key, ttlMs = 5000) {
  const now = Date.now();
  const until = held.get(key);
  if (until && until > now) return null;
  held.set(key, now + ttlMs);
  const timer = setTimeout(() => held.delete(key), ttlMs);
  timer.unref?.();
  let released = false;
  return async () => {
    if (released) return;
    released = true;
    clearTimeout(timer);
    held.delete(key);
  };
}

async function close() {
  held.clear();
}

module.exports = { acquire, close };

// Fail-safe: log if the map ever grows unbounded (a release() being dropped).
setInterval(() => {
  if (held.size > 500) logger.warn({ size: held.size }, 'lock map unexpectedly large');
}, 60_000).unref?.();
