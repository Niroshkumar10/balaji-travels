'use strict';

/**
 * Socket.IO wiring.
 *
 * Every socket authenticates at the handshake (socketAuth) — identity lives on
 * socket.data and is NEVER taken from an event payload. Handlers are thin: they
 * validate ownership through the same services the REST layer uses, then let
 * those services emit via realtime/emitter. Every handler is wrapped so a
 * throw becomes an ack error, never a process crash.
 */

const { Server } = require('socket.io');
const logger = require('../infra/logger');
const socketAuth = require('./socketAuth');
const realtime = require('../realtime/emitter');

const rideService = require('../services/rideService');
const dispatchService = require('../services/dispatchService');
const presenceService = require('../services/presenceService');
const trackingService = require('../services/trackingService');
const rideRepo = require('../repositories/rideRepo');

let io = null;

function wrap(socket, name, fn) {
  return async (payload = {}, ack) => {
    try {
      const result = (await fn(payload)) ?? {};
      if (typeof ack === 'function') ack({ ok: true, ...result });
    } catch (err) {
      logger.warn({ err: err.message, code: err.code, name, userId: socket.data.userId }, 'socket handler error');
      if (typeof ack === 'function') {
        ack({ ok: false, error: err.code || 'ERROR', message: err.expose ? err.message : 'Server error' });
      }
    }
  };
}

async function joinActiveRideRoom(socket) {
  const { role, profileId } = socket.data;
  const active =
    role === 'customer'
      ? await rideRepo.findActiveForCustomer(profileId)
      : await rideRepo.findActiveForDriver(profileId);
  if (active) realtime.joinRideRoom(socket, active.id);
  return active;
}

function registerCustomer(socket) {
  const requester = () => ({ role: 'customer', userId: socket.data.userId, profileId: socket.data.profileId });

  socket.on(
    'ride:request',
    wrap(socket, 'ride:request', async (p) => {
      const ride = await rideService.createRide({
        customer: { profileId: socket.data.profileId, userId: socket.data.userId },
        pickup: p.pickup,
        drop: p.drop,
        vehicleCategory: p.vehicleCategory,
        rideType: p.rideType,
        paymentMethod: p.paymentMethod,
        promoCode: p.promoCode,
      });
      realtime.joinRideRoom(socket, ride.id);
      return { ride };
    }),
  );

  socket.on(
    'ride:cancel',
    wrap(socket, 'ride:cancel', async (p) => {
      const ride = await rideService.cancelRide(Number(p.rideId), requester(), p.reason);
      realtime.leaveRideRoom(socket, ride.id);
      return { ride };
    }),
  );

  socket.on(
    'ride:resync',
    wrap(socket, 'ride:resync', async (p) => {
      const ride = await rideService.getRide(Number(p.rideId), requester());
      realtime.joinRideRoom(socket, ride.id);
      return { ride };
    }),
  );

  socket.on(
    'customer:location',
    wrap(socket, 'customer:location', async (p) => {
      await trackingService.customerPing({
        customerProfileId: socket.data.profileId,
        rideId: Number(p.rideId),
        lat: p.lat,
        lng: p.lng,
      });
    }),
  );
}

function registerDriver(socket) {
  const pid = () => socket.data.profileId;

  socket.on('driver:online', wrap(socket, 'driver:online', (p) => presenceService.goOnline(pid(), { lat: p.lat, lng: p.lng })));
  socket.on('driver:offline', wrap(socket, 'driver:offline', () => presenceService.goOffline(pid())));
  socket.on('driver:heartbeat', wrap(socket, 'driver:heartbeat', (p) => presenceService.heartbeat(pid(), p)));

  socket.on(
    'ride:offer_response',
    wrap(socket, 'ride:offer_response', async (p) => {
      const res = await dispatchService.handleOfferResponse(Number(p.rideId), pid(), p.accept === true);
      if (res.ok && res.ride) realtime.joinRideRoom(socket, res.ride.id);
      return res;
    }),
  );

  socket.on('ride:enroute', wrap(socket, 'ride:enroute', (p) => rideService.driverEnroute(Number(p.rideId), pid())));
  socket.on('ride:arrived', wrap(socket, 'ride:arrived', (p) => rideService.driverArrived(Number(p.rideId), pid())));
  socket.on('ride:start', wrap(socket, 'ride:start', (p) => rideService.startRide(Number(p.rideId), pid(), p.otp)));
  socket.on(
    'ride:complete',
    wrap(socket, 'ride:complete', (p) =>
      rideService.completeRide(Number(p.rideId), pid(), { waitingMinutes: p.waitingMinutes ?? 0 }),
    ),
  );

  socket.on(
    'driver:location',
    wrap(socket, 'driver:location', async (p) => {
      await trackingService.relay({
        driverProfileId: pid(),
        rideId: p.rideId ? Number(p.rideId) : null,
        lat: p.lat,
        lng: p.lng,
        bearing: p.bearing,
        speedKmph: p.speedKmph ?? p.speed,
      });
    }),
  );

  socket.on(
    'ride:resync',
    wrap(socket, 'ride:resync', async (p) => {
      const ride = await rideService.getRide(Number(p.rideId), {
        role: 'driver',
        userId: socket.data.userId,
        profileId: pid(),
      });
      realtime.joinRideRoom(socket, ride.id);
      return { ride };
    }),
  );
}

/** @param {import('http').Server} httpServer */
function initSockets(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: '*' },
    pingInterval: 20_000,
    pingTimeout: 25_000,
  });
  // Single-instance deployment — the default in-memory adapter is all we need.

  realtime.bind(io);
  io.use(socketAuth);

  io.on('connection', async (socket) => {
    const { userId, role } = socket.data;
    socket.join(`user:${userId}`);
    logger.debug({ userId, role, sid: socket.id }, 'socket connected');

    try {
      await joinActiveRideRoom(socket);
    } catch (err) {
      logger.debug({ err: err.message }, 'joinActiveRideRoom failed');
    }

    socket.on('ping', (_p, ack) => typeof ack === 'function' && ack({ ok: true, ts: Date.now(), userId, role }));

    if (role === 'customer') registerCustomer(socket);
    if (role === 'driver') registerDriver(socket);

    socket.on('disconnect', (reason) => {
      logger.debug({ userId, role, sid: socket.id, reason }, 'socket disconnected');
    });
  });

  return io;
}

function getIo() {
  if (!io) throw new Error('socket.io not initialised');
  return io;
}

module.exports = { initSockets, getIo };
