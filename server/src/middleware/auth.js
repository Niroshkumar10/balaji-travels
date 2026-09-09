'use strict';

/**
 * Bearer-token authentication.
 *
 * A valid JWT signature is necessary but NOT sufficient — the token must also
 * still be the one stored on rt_users.auth_token. That live comparison is what
 * makes logout, and "logged in on a newer device", revoke a token immediately
 * instead of leaving it usable until it expires.  (Pattern carried over from
 * Microlab's middleware/auth.js, which proved this out.)
 *
 * On success sets:
 *   req.auth = { userId, role, profileId }
 */

const jwtUtil = require('../utils/jwt');
const userRepo = require('../repositories/userRepo');
const ApiError = require('../utils/apiError');
const { parseUtc } = require('../utils/time');

async function authenticate(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) {
      throw ApiError.unauthorized('Missing bearer token', 'NO_TOKEN');
    }
    const token = header.slice(7).trim();

    let claims;
    try {
      claims = jwtUtil.verify(token);
    } catch {
      throw ApiError.unauthorized('Invalid or expired token', 'BAD_TOKEN');
    }

    const userId = Number(claims.sub);
    const state = await userRepo.findAuthState(userId);

    if (!state || state.status !== 'active') {
      throw ApiError.unauthorized('Account not active', 'ACCOUNT_INACTIVE');
    }
    if (state.auth_token !== token) {
      throw ApiError.unauthorized('Session expired or logged in elsewhere', 'SESSION_SUPERSEDED');
    }
    if (state.token_expiry && parseUtc(state.token_expiry).getTime() < Date.now()) {
      throw ApiError.unauthorized('Session expired', 'SESSION_EXPIRED');
    }

    req.auth = {
      userId,
      role: claims.role,
      profileId: claims.pid != null ? Number(claims.pid) : null,
    };
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = authenticate;
