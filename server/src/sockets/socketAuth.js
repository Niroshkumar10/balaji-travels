'use strict';

/**
 * Socket.IO handshake authentication.
 *
 * Microlab's socket layer had NO auth — every event trusted a client-sent
 * technicianId / driverId / patientId, so anyone could drive any booking.
 * Here the identity is established once, at connect time, from the same JWT +
 * live-DB-token check the REST layer uses, and pinned to `socket.data`. No
 * event handler ever reads an id from the payload.
 */

const jwtUtil = require('../utils/jwt');
const userRepo = require('../repositories/userRepo');
const logger = require('../infra/logger');
const { parseUtc } = require('../utils/time');

/**
 * @param {import('socket.io').Socket} socket
 * @param {(err?: Error) => void} next
 */
async function socketAuth(socket, next) {
  try {
    const token =
      socket.handshake.auth?.token ||
      (socket.handshake.headers.authorization || '').replace(/^Bearer\s+/i, '');

    if (!token) return next(new Error('AUTH_REQUIRED'));

    let claims;
    try {
      claims = jwtUtil.verify(token);
    } catch {
      return next(new Error('BAD_TOKEN'));
    }

    const userId = Number(claims.sub);
    const state = await userRepo.findAuthState(userId);
    if (!state || state.status !== 'active') return next(new Error('ACCOUNT_INACTIVE'));
    if (state.auth_token !== token) return next(new Error('SESSION_SUPERSEDED'));
    if (state.token_expiry && parseUtc(state.token_expiry).getTime() < Date.now()) {
      return next(new Error('SESSION_EXPIRED'));
    }

    socket.data.userId = userId;
    socket.data.role = claims.role;
    socket.data.profileId = claims.pid != null ? Number(claims.pid) : null;
    return next();
  } catch (err) {
    logger.error({ err }, 'socket auth error');
    return next(new Error('AUTH_ERROR'));
  }
}

module.exports = socketAuth;
