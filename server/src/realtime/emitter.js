'use strict';

/**
 * Thin indirection between services and Socket.IO.
 *
 * sockets/index.js calls `bind(io)` once at startup. Services then call
 * `toUser` / `toRide` without importing the socket layer, which keeps the
 * dependency graph acyclic (sockets → services, never the reverse).
 *
 * Rooms:
 *   user:<userId>   every socket that identity has open
 *   ride:<rideId>   the customer + assigned driver for a ride
 */

const logger = require('../infra/logger');

let io = null;

function bind(server) {
  io = server;
}

function toUser(userId, event, payload) {
  if (io) io.to(`user:${userId}`).emit(event, payload);
  else logger.debug({ event, userId }, 'emit skipped — io not bound');
}

function toRide(rideId, event, payload) {
  if (io) io.to(`ride:${rideId}`).emit(event, payload);
}

/** Emit to a specific connected socket id (used for the losing driver on an offer race). */
function toSocket(socketId, event, payload) {
  if (io && socketId) io.to(socketId).emit(event, payload);
}

function joinRideRoom(socket, rideId) {
  socket.join(`ride:${rideId}`);
}

function leaveRideRoom(socket, rideId) {
  socket.leave(`ride:${rideId}`);
}

module.exports = { bind, toUser, toRide, toSocket, joinRideRoom, leaveRideRoom, get io() { return io; } };
