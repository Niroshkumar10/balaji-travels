'use strict';

/**
 * Rate limiters. Backed by Redis when available (so limits hold across
 * instances), in-memory otherwise. Two presets:
 *
 *   apiLimiter  — broad safety net on the whole /api surface
 *   otpLimiter  — strict, per-mobile, on OTP request (abuse / SMS-cost control)
 */

const rateLimit = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const redis = require('../infra/redis');
const env = require('../config/env');
const ApiError = require('../utils/apiError');

// Rate limiting is disabled under NODE_ENV=test so suites are deterministic
// (the limits themselves are covered by dedicated tests that opt back in).
const passthrough = (_req, _res, next) => next();

function store(prefix) {
  if (!redis.isEnabled) return undefined; // express-rate-limit falls back to memory
  return new RedisStore({
    prefix,
    sendCommand: (...args) => redis.client.call(...args),
  });
}

const handler = (_req, _res, next) => next(ApiError.tooMany());

const apiLimiter = env.isTest
  ? passthrough
  : rateLimit({
      windowMs: 60_000,
      limit: 120,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      store: store('rl:api:'),
      handler,
    });

const otpLimiter = env.isTest
  ? passthrough
  : rateLimit({
      windowMs: 10 * 60_000,
      limit: 5,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      store: store('rl:otp:'),
      // key by mobile number in the body, not just IP (NAT / shared IPs)
      keyGenerator: (req) => `${req.ip}:${(req.body && req.body.mobile) || 'nomobile'}`,
      handler,
    });

module.exports = { apiLimiter, otpLimiter };
