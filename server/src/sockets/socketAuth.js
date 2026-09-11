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

const env = require('../config/env');
const jwtUtil = require('../utils/jwt');
const userRepo = require('../repositories/userRepo');
const logger = require('../infra/logger');
const L = logger.for('socket'); // → logs/socket.log
const { parseUtc } = require('../utils/time');

/** Log + reject a handshake so failed connects are visible, not silent. */
function deny(next, reason, extra = {}) {
  L.warnEvent('🚫', `handshake rejected — ${reason}`, extra);
  return next(new Error(reason));
}

/**
 * @param {import('socket.io').Socket} socket
 * @param {(err?: Error) => void} next
 */
async function socketAuth(socket, next) {
  try {
    const token =
      socket.handshake.auth?.token ||
      (socket.handshake.headers.authorization || '').replace(/^Bearer\s+/i, '');

    L.event('🔑', 'handshake received', {
      transport: socket.conn?.transport?.name,
      hasAuthToken: !!socket.handshake.auth?.token,
      hasAuthHeader: !!socket.handshake.headers.authorization,
    });

    if (!token) return deny(next, 'AUTH_REQUIRED');

    let claims;
    try {
      claims = jwtUtil.verify(token);
    } catch {
      return deny(next, 'BAD_TOKEN');
    }

    const userId = Number(claims.sub);
    const state = await userRepo.findAuthState(userId);
    if (!state || state.status !== 'active') return deny(next, 'ACCOUNT_INACTIVE', { userId });
    if (state.token_expiry && parseUtc(state.token_expiry).getTime() < Date.now()) {
      return deny(next, 'SESSION_EXPIRED', { userId });
    }
    // Single-session enforcement for sockets is opt-in (SOCKET_STRICT_SESSION).
    // Off by default: a re-login on the same phone rotates rt_users.auth_token,
    // which would otherwise drop a socket that is really the same user. REST
    // still enforces it, so a stolen token is still cut off there.
    if (env.SOCKET_STRICT_SESSION && state.auth_token !== token) {
      return deny(next, 'SESSION_SUPERSEDED', {
        userId,
        hint: 'SOCKET_STRICT_SESSION=true and this account logged in again elsewhere',
      });
    }

    socket.data.userId = userId;
    socket.data.role = claims.role;
    socket.data.profileId = claims.pid != null ? Number(claims.pid) : null;
    L.event('✅', 'handshake authenticated', {
      userId,
      role: socket.data.role,
      driverId: socket.data.role === 'driver' ? socket.data.profileId : undefined,
    });
    return next();
  } catch (err) {
    logger.error({ err }, 'socket auth error');
    return next(new Error('AUTH_ERROR'));
  }
}

module.exports = socketAuth;
