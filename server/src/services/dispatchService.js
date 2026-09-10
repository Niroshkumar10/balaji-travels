'use strict';

/**
 * Driver dispatch engine.
 *
 * Algorithm (adapted from Microlab's proven bookingSocket.js dispatch, with the
 * healthcare lanes removed and the race guard moved to the database):
 *   • build a distance-sorted queue of online + available + KYC-approved drivers
 *     within the search radius whose vehicle category matches the request
 *   • offer to ONE driver at a time; each offer has a hard timeout
 *   • active reject or timeout → next driver
 *   • nearby queue exhausted → re-query WIDER (DISPATCH_EXPAND_RADIUS_KM;
 *     0 = no distance limit, i.e. any online driver of the right category);
 *     still none → NO_DRIVERS_FOUND
 *   • acceptance is resolved by rideRepo.atomicAssign — a conditional UPDATE
 *     that exactly one concurrent caller can win; a short Redis lock just makes
 *     the losing side cheap. No in-memory Set is load-bearing.
 *
 * In-memory dispatch state is per-process; a multi-instance deployment should
 * run dispatch on a single worker or shard by ride id. This is documented, not
 * hidden.
 */

const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../infra/logger');
const L = logger.for('dispatch'); // → logs/dispatch.log
const lock = require('../infra/lock');
const db = require('../infra/db');
const realtime = require('../realtime/emitter');
const geo = require('./geoService');
const notifyService = require('./notifyService');
const rideRepo = require('../repositories/rideRepo');
const rideOfferRepo = require('../repositories/rideOfferRepo');
const driverRepo = require('../repositories/driverRepo');
const vehicleRepo = require('../repositories/vehicleRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');
const customerRepo = require('../repositories/customerRepo');
const userRepo = require('../repositories/userRepo');

const OFFER_TIMEOUT_MS = env.DISPATCH_OFFER_TIMEOUT_MS;
const NO_DRIVER_TIMEOUT_MS = env.DISPATCH_NO_DRIVER_TIMEOUT_MS;
const RADIUS_KM = env.DISPATCH_SEARCH_RADIUS_KM;
// Radius for the re-query once the nearby queue is exhausted. 0 = no limit.
const EXPAND_RADIUS_KM = env.DISPATCH_EXPAND_RADIUS_KM;
const MAX_DRIVERS = env.DISPATCH_MAX_DRIVERS;

const radiusLabel = (r) => (r > 0 ? `${r} km` : 'no distance limit');

/** rideId -> dispatch state */
const state = new Map();

const ride4 = () => String(crypto.randomInt(0, 10000)).padStart(4, '0');

function clearTimers(s) {
  if (s.offerTimer) clearTimeout(s.offerTimer);
  if (s.globalTimer) clearTimeout(s.globalTimer);
  s.offerTimer = null;
  s.globalTimer = null;
}

const km = (m) => (m == null ? 'no GPS' : `${(m / 1000).toFixed(1)} km`);

/** Compact, self-contained view of the offer queue for a log block. */
function queueSnapshot(s) {
  const remaining = Math.max(0, s.queue.length - s.idx);
  const lines = [
    `Queue : ${s.queue.length} total  |  tried ${s.idx}  |  remaining ${remaining}`,
  ];
  s.queue.forEach((c, i) => {
    const mark = i < s.idx ? '✓' : i === s.idx ? '▶' : '○';
    lines.push(`  ${mark} ${i + 1}. driver ${c.driverId}   ${km(c.distanceM)} from pickup`);
  });
  return lines;
}

async function buildQueue(ride, excludeIds = new Set(), radiusKm = RADIUS_KM) {
  const rows = await driverLocationRepo.nearby({
    lat: Number(ride.pickup_lat),
    lng: Number(ride.pickup_lng),
    radiusKm,
    categories: [ride.vehicle_category],
    limit: MAX_DRIVERS * 2,
  });
  const queue = rows
    .filter((r) => !excludeIds.has(r.driver_id))
    .slice(0, MAX_DRIVERS)
    .map((r) => ({
      driverId: r.driver_id,
      vehicleId: r.vehicle_id ?? r.current_vehicle_id,
      distanceM: r.distance_m,
      lat: Number(r.lat),
      lng: Number(r.lng),
    }));
  L.block('🔍', `Ride #${ride.id} — driver search`, [
    `Pickup    : ${Number(ride.pickup_lat).toFixed(5)}, ${Number(ride.pickup_lng).toFixed(5)}`,
    `Category  : ${ride.vehicle_category}    Radius : ${radiusLabel(radiusKm)}`,
    `Found     : ${rows.length} matching  →  queued ${queue.length}`,
    ...queue.map((c, i) => `  ${i + 1}. driver ${c.driverId}   ${km(c.distanceM)} from pickup`),
  ]);
  return queue;
}

/** Run the staged diagnostic and log which filter eliminated every driver. */
async function logWhyNoDrivers(ride, radiusKm = RADIUS_KM) {
  try {
    const d = await driverLocationRepo.diagnose({
      lat: Number(ride.pickup_lat),
      lng: Number(ride.pickup_lng),
      radiusKm,
      category: ride.vehicle_category,
    });
    const distLine =
      d.radiusKm == null
        ? `  (no distance limit) ....... ${d.insideRadiusBox}`
        : `  within ${d.radiusKm} km of pickup ..... ${d.insideRadiusBox}`;
    L.block('❌', `Ride #${ride.id} — no candidates (first 0 = the reason)`, [
      `online .................... ${d.online}`,
      `  available ............... ${d.available}`,
      `  KYC approved ............ ${d.kycApproved}`,
      `  has a GPS row .......... ${d.hasLocationRow}`,
      `  GPS fresh (< ${d.staleSeconds}s) ...... ${d.freshLocation}`,
      distLine,
      `  vehicle = ${d.category} ......... ${d.categoryMatch}`,
    ]);
  } catch (err) {
    L.warnEvent('⚠️', 'diagnostic query failed', { rideId: ride.id, err: err.message });
  }
}

async function start(ride) {
  L.block('🚕', `Ride #${ride.id} — searching for a driver`, [
    `Pickup       : ${Number(ride.pickup_lat).toFixed(5)}, ${Number(ride.pickup_lng).toFixed(5)}`,
    `Drop         : ${Number(ride.drop_lat).toFixed(5)}, ${Number(ride.drop_lng).toFixed(5)}`,
    `Category     : ${ride.vehicle_category}    Trip : ${km(ride.distance_m)}`,
    `Search radius: ${RADIUS_KM} km  (then ${radiusLabel(EXPAND_RADIUS_KM)} on re-query)`,
    `Per-offer    : ${OFFER_TIMEOUT_MS / 1000}s     Give up after : ${NO_DRIVER_TIMEOUT_MS / 1000}s`,
  ]);
  // REQUESTED → SEARCHING_DRIVER
  const searching = await db.withTransaction((tx) =>
    rideRepo.transition({ rideId: ride.id, event: 'search', actorRole: 'system' }, tx),
  );

  const customer = await customerRepo.findById(ride.customer_id);
  realtime.toUser(customer.user_id, 'ride:searching', { rideId: ride.id, status: searching.status });

  const queue = await buildQueue(searching);
  if (queue.length === 0) {
    await logWhyNoDrivers(searching);
    await noDrivers(ride.id);
    return;
  }

  const s = {
    ride: searching,
    customerUserId: customer.user_id,
    queue,
    idx: 0,
    offeredUserIds: new Map(), // driverId -> driverUserId
    offerTimer: null,
    globalTimer: setTimeout(() => noDrivers(ride.id).catch((e) => logger.error({ e }, 'noDrivers')), NO_DRIVER_TIMEOUT_MS),
  };
  state.set(ride.id, s);
  L.event('▶️', 'dispatch started', { rideId: ride.id, candidates: queue.length });
  offerNext(ride.id).catch((e) => logger.error({ err: e }, 'offerNext failed'));
}

async function offerNext(rideId) {
  const s = state.get(rideId);
  if (!s) return;

  if (s.idx >= s.queue.length) {
    // Nearby list exhausted — widen the net (EXPAND_RADIUS_KM; 0 = no limit).
    const excl = new Set(s.queue.map((c) => c.driverId));
    const fresh = await buildQueue(s.ride, excl, EXPAND_RADIUS_KM);
    if (fresh.length === 0) {
      await logWhyNoDrivers(s.ride, EXPAND_RADIUS_KM);
      await noDrivers(rideId);
      return;
    }
    s.queue.push(...fresh);
    L.event('🔄', `re-queried (${radiusLabel(EXPAND_RADIUS_KM)}) after exhausting nearby`, {
      rideId,
      added: fresh.length,
    });
  }

  const cand = s.queue[s.idx];

  // Re-check the driver is still dispatchable right before the offer.
  const drv = await driverRepo.findById(cand.driverId);
  if (!drv || drv.is_online !== 1 || drv.availability !== 'available' || drv.kyc_status !== 'approved') {
    L.event('⏭️', 'skipped — driver no longer dispatchable', {
      rideId,
      driverId: cand.driverId,
      isOnline: drv?.is_online,
      availability: drv?.availability,
      kyc: drv?.kyc_status,
    });
    s.idx += 1;
    return offerNext(rideId);
  }
  const drvUser = await userRepo.findById(drv.user_id);
  s.offeredUserIds.set(cand.driverId, drv.user_id);

  await rideOfferRepo.create({ rideId, driverId: cand.driverId, distanceM: cand.distanceM });

  const etaSec = geo.etaSeconds({ lat: cand.lat, lng: cand.lng }, { lat: Number(s.ride.pickup_lat), lng: Number(s.ride.pickup_lng) });
  realtime.toUser(drv.user_id, 'ride:offer', {
    rideId,
    pickup: { lat: Number(s.ride.pickup_lat), lng: Number(s.ride.pickup_lng), addr: s.ride.pickup_addr },
    drop: { lat: Number(s.ride.drop_lat), lng: Number(s.ride.drop_lng), addr: s.ride.drop_addr },
    distanceToPickupM: cand.distanceM,
    tripDistanceM: s.ride.distance_m,
    estFare: s.ride.est_fare,
    vehicleCategory: s.ride.vehicle_category,
    expiresInSec: Math.round(OFFER_TIMEOUT_MS / 1000),
  });
  notifyService.notify(drv.user_id, {
    type: 'ride_offer',
    title: 'New ride request',
    body: `Pickup ${(cand.distanceM / 1000).toFixed(1)} km away`,
    data: { rideId: String(rideId) },
  });

  const next = s.queue[s.idx + 1] ?? null;
  L.block('📤', `Ride #${rideId} — offer ${s.idx + 1}/${s.queue.length}`, [
    `▶ Offering : driver ${cand.driverId}   ${km(cand.distanceM)} from pickup`,
    `  Window   : ${OFFER_TIMEOUT_MS / 1000}s to respond`,
    `  Channel  : socket + FCM push`,
    `⬇ Next     : ${next ? `driver ${next.driverId}  ${km(next.distanceM)}` : 'none — will re-query on exhaustion'}`,
    '',
    ...queueSnapshot(s),
  ]);

  s.offerTimer = setTimeout(() => {
    L.event('⏰', 'offer timed out — moving to next', { rideId, driverId: cand.driverId });
    rideOfferRepo.markResponded(rideId, cand.driverId, 'timed_out').catch(() => {});
    realtime.toUser(s.offeredUserIds.get(cand.driverId), 'ride:offer_revoked', { rideId, reason: 'timeout' });
    s.idx += 1;
    offerNext(rideId).catch((e) => logger.error({ err: e }, 'offerNext (post-timeout)'));
  }, OFFER_TIMEOUT_MS);
}

/**
 * @returns {Promise<{ok:boolean, reason?:string, ride?:object}>}
 */
async function handleOfferResponse(rideId, driverId, accept) {
  L.event(accept ? '👍' : '👎', `driver ${accept ? 'accepted' : 'rejected'} the offer`, { rideId, driverId });
  const s = state.get(rideId);
  if (!s) {
    L.warnEvent('⚠️', 'response for a ride with no active dispatch (expired / already taken)', { rideId, driverId });
    return { ok: false, reason: 'expired' };
  }

  if (!accept) {
    await rideOfferRepo.markResponded(rideId, driverId, 'rejected').catch(() => {});
    const cand = s.queue[s.idx];
    if (cand && cand.driverId === driverId) {
      clearTimeout(s.offerTimer);
      s.idx += 1;
      offerNext(rideId).catch((e) => logger.error({ err: e }, 'offerNext (post-reject)'));
    }
    return { ok: true, reason: 'declined' };
  }

  const release = await lock.acquire(`ride:${rideId}`, 4000);
  if (!release) return { ok: false, reason: 'taken' };

  try {
    const result = await db.withTransaction(async (tx) => {
      const drv = await driverRepo.findById(driverId, tx);
      const vehId = drv?.current_vehicle_id ?? null;

      const won = await rideRepo.atomicAssign({ rideId, driverId, vehicleId: vehId }, tx);
      if (!won) return { ok: false, reason: 'taken' };

      await rideOfferRepo.markResponded(rideId, driverId, 'accepted', tx);
      await rideOfferRepo.supersedeOthers(rideId, driverId, tx);

      const otp = ride4();
      await rideRepo.setOtp(rideId, otp, tx);
      const ride = await rideRepo.findById(rideId, tx);
      return { ok: true, ride, otp, driver: drv, vehicleId: vehId };
    });

    if (!result.ok) return result;

    clearTimers(s);
    state.delete(rideId);

    const { ride, otp } = result;
    const [drvUser, drvLoc, vehicle] = await Promise.all([
      userRepo.findById(result.driver.user_id),
      driverLocationRepo.get(driverId),
      result.vehicleId ? vehicleRepo.findById(result.vehicleId) : null,
    ]);

    const etaSec = drvLoc
      ? geo.etaSeconds({ lat: Number(drvLoc.lat), lng: Number(drvLoc.lng) }, { lat: Number(ride.pickup_lat), lng: Number(ride.pickup_lng) })
      : null;

    // customer
    realtime.toUser(s.customerUserId, 'ride:driver_assigned', {
      rideId,
      status: ride.status,
      otp,
      driver: {
        id: driverId,
        name: drvUser?.name ?? 'Driver',
        rating: Number(result.driver.rating_avg),
        phoneMasked: maskPhone(drvUser?.mobile),
      },
      vehicle: vehicle
        ? { category: vehicle.category, plateNo: vehicle.plate_no, make: vehicle.make, model: vehicle.model, color: vehicle.color }
        : null,
      driverLocation: drvLoc ? { lat: Number(drvLoc.lat), lng: Number(drvLoc.lng), bearing: drvLoc.bearing } : null,
      etaToPickupSec: etaSec,
    });
    notifyService.notify(s.customerUserId, {
      type: 'driver_assigned',
      title: 'Driver on the way',
      body: `${drvUser?.name ?? 'Your driver'} · ${vehicle?.plate_no ?? ''}`.trim(),
      data: { rideId: String(rideId) },
    });

    // winning driver
    const customerUser = await userRepo.findById((await customerRepo.findById(ride.customer_id)).user_id);
    realtime.toUser(result.driver.user_id, 'ride:assigned', {
      rideId,
      status: ride.status,
      customer: { name: customerUser?.name ?? 'Customer', phoneMasked: maskPhone(customerUser?.mobile) },
      pickup: { lat: Number(ride.pickup_lat), lng: Number(ride.pickup_lng), addr: ride.pickup_addr },
      drop: { lat: Number(ride.drop_lat), lng: Number(ride.drop_lng), addr: ride.drop_addr },
      distanceM: ride.distance_m,
      estFare: ride.est_fare,
      otp, // shown so the driver knows what to ask for
    });

    // everyone else who was offered
    for (const [dId, uId] of s.offeredUserIds) {
      if (dId !== driverId) realtime.toUser(uId, 'ride:offer_revoked', { rideId, reason: 'taken' });
    }

    L.block('✅', `Ride #${rideId} — ASSIGNED to driver ${driverId}`, [
      `Driver   : ${drvUser?.name ?? 'Driver'} (id ${driverId})`,
      `Vehicle  : ${vehicle ? `${vehicle.category} ${vehicle.plate_no}` : '—'}`,
      `ETA      : ${etaSec != null ? `${Math.round(etaSec / 60)} min to pickup` : 'unknown'}`,
      `OTP      : issued to customer + driver`,
      `Others   : ${s.offeredUserIds.size - 1} earlier offer(s) revoked`,
    ]);
    return { ok: true, ride };
  } finally {
    await release();
  }
}

async function noDrivers(rideId) {
  const s = state.get(rideId);
  if (s) {
    clearTimers(s);
    state.delete(rideId);
  }
  const updated = await db.withTransaction(async (tx) => {
    const cur = await rideRepo.findById(rideId, tx);
    if (!cur || cur.status !== 'SEARCHING_DRIVER') return cur;
    await rideOfferRepo.timeoutAllSent(rideId, tx);
    return rideRepo.transition({ rideId, event: 'no_drivers', actorRole: 'system' }, tx);
  });
  if (!updated || updated.status !== 'NO_DRIVERS_FOUND') return;

  const customer = await customerRepo.findById(updated.customer_id);
  realtime.toUser(customer.user_id, 'ride:no_drivers', { rideId, status: updated.status });
  notifyService.notify(customer.user_id, {
    type: 'no_drivers',
    title: 'No drivers available',
    body: 'We could not find a driver nearby. Please try again.',
    data: { rideId: String(rideId) },
  });
  L.event('🛑', 'gave up — NO_DRIVERS_FOUND (customer notified)', { rideId });
}

/** Called when the customer cancels while still searching. */
function cancelDispatch(rideId) {
  const s = state.get(rideId);
  if (!s) return;
  clearTimers(s);
  state.delete(rideId);
  rideOfferRepo.timeoutAllSent(rideId).catch(() => {});
  for (const [, uId] of s.offeredUserIds) {
    realtime.toUser(uId, 'ride:offer_revoked', { rideId, reason: 'cancelled' });
  }
}

function isDispatching(rideId) {
  return state.has(rideId);
}

function maskPhone(m) {
  if (!m) return null;
  return `${m.slice(0, 2)}xxxxx${m.slice(-3)}`;
}

module.exports = { start, handleOfferResponse, cancelDispatch, noDrivers, isDispatching };
