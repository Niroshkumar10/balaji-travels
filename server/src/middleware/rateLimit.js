'use strict';

/**
 * Rate limiters (in-memory — single instance). Two presets:
 *
 *   apiLimiter  — broad safety net on the whole /api surface
 *   otpLimiter  — strict, per-mobile, on OTP request (abuse / SMS-cost control)
 */

const rateLimit = require('express-rate-limit');
const env = require('../config/env');
const ApiError = require('../utils/apiError');

// Rate limiting is disabled under NODE_ENV=test so suites are deterministic
// (the limits themselves are covered by dedicated tests that opt back in).
const passthrough = (_req, _res, next) => next();

const handler = (_req, _res, next) => next(ApiError.tooMany());

const apiLimiter = env.isTest
  ? passthrough
  : rateLimit({
      windowMs: 60_000,
      limit: 120,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      handler,
    });

const otpLimiter = env.isTest
  ? passthrough
  : rateLimit({
      windowMs: 10 * 60_000,
      limit: 5,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      // key by mobile number in the body, not just IP (NAT / shared IPs)
      keyGenerator: (req) => `${req.ip}:${(req.body && req.body.mobile) || 'nomobile'}`,
      handler,
    });

module.exports = { apiLimiter, otpLimiter };
