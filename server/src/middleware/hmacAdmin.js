'use strict';

/**
 * Server-to-server auth for the admin web / batch jobs (no end-user JWT).
 *
 * Each request must carry:
 *   X-Admin-Timestamp : unix seconds
 *   X-Admin-Signature : hex HMAC-SHA256( `${method}\n${path}\n${timestamp}\n${rawBody}` , ADMIN_HMAC_SECRET )
 *
 * A 5-minute timestamp window blocks replay; comparison is timing-safe.
 * (Pattern carried from Microlab's middleware/adminAuth.js.)
 */

const crypto = require('crypto');
const env = require('../config/env');
const ApiError = require('../utils/apiError');

module.exports = function hmacAdmin(req, _res, next) {
  const sig = req.headers['x-admin-signature'];
  const ts = req.headers['x-admin-timestamp'];
  if (!sig || !ts) return next(ApiError.forbidden('Admin signature missing', 'ADMIN_SIG_MISSING'));

  const now = Math.floor(Date.now() / 1000);
  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum) || Math.abs(now - tsNum) > 300) {
    return next(ApiError.forbidden('Admin signature expired', 'ADMIN_SIG_EXPIRED'));
  }

  const rawBody = req.rawBody ?? JSON.stringify(req.body ?? {});
  const payload = `${req.method}\n${req.originalUrl.split('?')[0]}\n${ts}\n${rawBody}`;
  const expected = crypto.createHmac('sha256', env.ADMIN_HMAC_SECRET).update(payload).digest('hex');

  let ok = false;
  try {
    ok = crypto.timingSafeEqual(Buffer.from(sig, 'hex'), Buffer.from(expected, 'hex'));
  } catch {
    ok = false;
  }
  if (!ok) return next(ApiError.forbidden('Invalid admin signature', 'ADMIN_SIG_INVALID'));
  next();
};
