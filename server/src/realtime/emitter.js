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

/**
 * How many live sockets that identity currently has in its `user:<id>` room.
 * 0 means a `toUser` emit reaches nobody — the client isn't connected (or its
 * socket handshake is failing). Used by dispatch to log why an offer was never
 * seen.
 */
function userSocketCount(userId) {
  if (!io) return 0;
  const room = io.sockets.adapter.rooms.get(`user:${userId}`);
  return room ? room.size : 0;
}

/** The socket ids in that identity's room (for delivery logging). */
function userSocketIds(userId) {
  if (!io) return [];
  const room = io.sockets.adapter.rooms.get(`user:${userId}`);
  return room ? [...room] : [];
}

/**
 * Emit to a user AND report what happened: how many sockets received it.
 * Returns { room, delivered, socketIds }.
 */
function toUserVerbose(userId, event, payload) {
  const socketIds = userSocketIds(userId);
  if (io) io.to(`user:${userId}`).emit(event, payload);
  return { room: `user:${userId}`, delivered: socketIds.length, socketIds };
}

/** Total connected sockets, and a compact per-user breakdown (debugging). */
function registrySnapshot() {
  if (!io) return { total: 0, users: [] };
  const users = [];
  for (const [room, ids] of io.sockets.adapter.rooms) {
    if (room.startsWith('user:')) users.push(`${room}=${ids.size}`);
  }
  return { total: io.sockets.sockets.size, users };
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

module.exports = {
  bind,
  toUser,
  toUserVerbose,
  toRide,
  toSocket,
  userSocketCount,
  userSocketIds,
  registrySnapshot,
  joinRideRoom,
  leaveRideRoom,
  get io() {
    return io;
  },
};
