'use strict';

const crypto = require('crypto');
const env = require('../config/env');

/** Cryptographically-random numeric OTP of the configured length. */
function generateCode() {
  const len = env.OTP_LENGTH;
  const max = 10 ** len;
  // rejection-free: crypto.randomInt is unbiased in [0, max)
  return String(crypto.randomInt(0, max)).padStart(len, '0');
}

/**
 * Deterministic hash stored in rt_otps.code_hash. Bound to mobile + role +
 * server secret so a leaked hash can't be replayed elsewhere and can't be
 * reversed with a small rainbow table of 4-digit codes.
 */
function hashCode(code, mobile, role) {
  return crypto
    .createHmac('sha256', env.JWT_SECRET)
    .update(`${code}|${mobile}|${role}`)
    .digest('hex');
}

function timingSafeEqualHex(a, b) {
  const ba = Buffer.from(String(a), 'hex');
  const bb = Buffer.from(String(b), 'hex');
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

module.exports = { generateCode, hashCode, timingSafeEqualHex };
