'use strict';

/**
 * Redis access, with a graceful single-instance fallback.
 *
 * When REDIS_URL is set, this exports a real ioredis client (used for the
 * Socket.IO adapter, the rate-limit store, and short-lived dispatch locks).
 *
 * When REDIS_URL is NOT set (local dev), `client` is null and `lock()` falls
 * back to an in-process Map. That fallback is correct ONLY for a single Node
 * instance — production/staging must set REDIS_URL so the atomic guarantees
 * hold across instances. `isEnabled` lets callers branch where it matters.
 */

const Redis = require('ioredis');
const env = require('../config/env');
const logger = require('./logger');

let client = null;
let subClient = null;

if (env.REDIS_URL) {
  client = new Redis(env.REDIS_URL, { maxRetriesPerRequest: 3, lazyConnect: false });
  client.on('error', (err) => logger.error({ err }, 'redis error'));
  client.on('connect', () => logger.info('redis connected'));
  // Separate connection for the pub/sub side of the Socket.IO adapter.
  subClient = client.duplicate();
  subClient.on('error', (err) => logger.error({ err }, 'redis sub error'));
} else {
  logger.warn('REDIS_URL not set — using in-process fallbacks (single instance only)');
}

const isEnabled = Boolean(client);

// ── In-process lock fallback ────────────────────────────────────────────────
const localLocks = new Map(); // key -> expiry epoch ms

/**
 * Acquire a short-lived exclusive lock. Returns a release() function, or null
 * if the lock is already held.
 *
 * @param {string} key
 * @param {number} ttlMs
 * @returns {Promise<null | (() => Promise<void>)>}
 */
async function lock(key, ttlMs = 5000) {
  const redisKey = `lock:${key}`;
  if (isEnabled) {
    const token = `${process.pid}-${Date.now()}-${Math.random()}`;
    const ok = await client.set(redisKey, token, 'PX', ttlMs, 'NX');
    if (!ok) return null;
    return async () => {
      // Only release if we still own it (Lua compare-and-delete).
      const lua =
        "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end";
      try {
        await client.eval(lua, 1, redisKey, token);
      } catch (err) {
        logger.warn({ err, key }, 'lock release failed');
      }
    };
  }

  const now = Date.now();
  const held = localLocks.get(redisKey);
  if (held && held > now) return null;
  localLocks.set(redisKey, now + ttlMs);
  return async () => {
    localLocks.delete(redisKey);
  };
}

async function close() {
  if (client) await client.quit().catch(() => {});
  if (subClient) await subClient.quit().catch(() => {});
}

module.exports = { client, subClient, isEnabled, lock, close };
