'use strict';

/* eslint-disable no-console */

/**
 * Headless driver — seeds a dispatchable driver profile, then acts as one.
 *
 * Why this exists: the ride-request path is SQL-only and a driver is only
 * dispatchable when ALL of these hold at request time (see
 * repositories/driverLocationRepo.nearby + services/dispatchService):
 *   • rt_drivers.kyc_status = 'approved'
 *   • rt_drivers.is_online  = 1
 *   • rt_drivers.availability = 'available'
 *   • an active rt_vehicles row, and rt_drivers.current_vehicle_id -> it
 *   • an rt_driver_locations row within DISPATCH_SEARCH_RADIUS_KM of pickup
 *     whose updated_at is younger than 60s
 * A one-off SQL seed satisfies the first four but the location goes stale after
 * a minute. So this script also connects as the driver over Socket.IO, goes
 * online, and heartbeats its position — exactly what the real driver app does.
 *
 * It uses the REAL code paths for everything that matters: OTP login + live
 * session token, socket handshake auth, presence, and every ride:* intent. The
 * only shortcut is the OTP itself (OTP_DEV_BYPASS_CODE from .env).
 *
 *   node scripts/driver-sim.js                 # seed + go online + auto-handle rides
 *   node scripts/driver-sim.js --seed-only     # just create/repair the profile, exit
 *   node scripts/driver-sim.js --no-lifecycle  # accept offers, then leave the ride to you
 *   node scripts/driver-sim.js --no-accept     # stay online, but don't touch offers
 *
 * Knobs (env or .env), shown with defaults:
 *   SIM_MOBILE=9999900001   SIM_NAME="Sim Driver"   SIM_CATEGORY=hatchback
 *   SIM_PLATE=TN99SIM0001   SIM_LAT=10.7342   SIM_LNG=77.0872
 *   SIM_ACCEPT_DELAY_MS=2000        wait before accepting an offer
 *   SIM_STEP_MS=4000               gap between en-route / arrived / start / complete
 *
 * SIM_CATEGORY MUST match the vehicle category the customer requests, or
 * dispatch will filter this driver out.
 */

const path = require('path');
const mysql = require('mysql2/promise');
const { io } = require('socket.io-client');

// Loads + validates .env (DB creds, PORT, OTP_DEV_BYPASS_CODE, ...). Exits loud
// if the environment is misconfigured — same guard the server boots behind.
const env = require(path.join('..', 'src', 'config', 'env'));

const args = new Set(process.argv.slice(2));
const SEED_ONLY = args.has('--seed-only');
const AUTO_ACCEPT = !args.has('--no-accept');
const AUTO_LIFECYCLE = !args.has('--no-lifecycle');

const CFG = {
  mobile: process.env.SIM_MOBILE || '9999900001',
  name: process.env.SIM_NAME || 'Sim Driver',
  category: process.env.SIM_CATEGORY || 'hatchback',
  plate: process.env.SIM_PLATE || 'TN99SIM0001',
  lat: Number(process.env.SIM_LAT || 10.7342),
  lng: Number(process.env.SIM_LNG || 77.0872),
  acceptDelayMs: Number(process.env.SIM_ACCEPT_DELAY_MS || 2000),
  stepMs: Number(process.env.SIM_STEP_MS || 4000),
};

const API = env.API_BASE_URL || `http://localhost:${env.PORT}`;
const BYPASS = env.OTP_DEV_BYPASS_CODE;

const log = (...m) => console.log(new Date().toISOString().slice(11, 19), ...m);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── 1. Seed / repair the driver profile directly in MySQL ────────────────────
async function seedProfile() {
  const db = await mysql.createConnection({
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    namedPlaceholders: true,
  });

  try {
    // user (unique on mobile+role)
    await db.execute(
      `INSERT INTO rt_users (mobile, role, name, status)
       VALUES (:mobile, 'driver', :name, 'active')
       ON DUPLICATE KEY UPDATE name = VALUES(name), status = 'active'`,
      { mobile: CFG.mobile, name: CFG.name },
    );
    const [[user]] = await db.query(
      `SELECT id FROM rt_users WHERE mobile = :mobile AND role = 'driver'`,
      { mobile: CFG.mobile },
    );

    // driver (unique on user_id) — force it dispatchable
    await db.execute(
      `INSERT INTO rt_drivers (user_id, kyc_status, license_no, kyc_reviewed_at)
         VALUES (:uid, 'approved', 'SIM-LICENSE-01', NOW())
       ON DUPLICATE KEY UPDATE kyc_status = 'approved', kyc_reviewed_at = NOW()`,
      { uid: user.id },
    );
    const [[driver]] = await db.query(`SELECT id FROM rt_drivers WHERE user_id = :uid`, { uid: user.id });

    // vehicle (unique on plate_no)
    await db.execute(
      `INSERT INTO rt_vehicles (driver_id, category, make, model, plate_no, color, doc_status, is_active)
         VALUES (:did, :cat, 'Maruti', 'Swift', :plate, 'White', 'approved', 1)
       ON DUPLICATE KEY UPDATE driver_id = VALUES(driver_id), category = VALUES(category),
         doc_status = 'approved', is_active = 1, deleted_at = NULL`,
      { did: driver.id, cat: CFG.category, plate: CFG.plate },
    );
    const [[vehicle]] = await db.query(`SELECT id FROM rt_vehicles WHERE plate_no = :plate`, { plate: CFG.plate });

    await db.execute(`UPDATE rt_drivers SET current_vehicle_id = :vid WHERE id = :did`, {
      vid: vehicle.id,
      did: driver.id,
    });

    // make sure the driver_wallet row the earnings path expects exists
    await db.execute(
      `INSERT IGNORE INTO rt_driver_wallet (driver_id, balance) VALUES (:did, 0)`,
      { did: driver.id },
    ).catch(() => {}); // table/columns vary by schema rev — non-fatal for the sim

    log(
      `seeded driver#${driver.id} (user#${user.id}) mobile=${CFG.mobile} ` +
        `vehicle#${vehicle.id} ${CFG.category} ${CFG.plate} — KYC approved`,
    );
    return { userId: user.id, driverId: driver.id, vehicleId: vehicle.id };
  } finally {
    await db.end();
  }
}

// ── 2. Real OTP login → live session token ──────────────────────────────────
async function login() {
  if (!BYPASS) {
    throw new Error('OTP_DEV_BYPASS_CODE is not set in .env — cannot log in headlessly');
  }
  const post = async (p, body) => {
    const res = await fetch(`${API}${p}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`${p} → ${res.status} ${JSON.stringify(json)}`);
    return json;
  };
  await post('/api/v1/auth/otp/request', { mobile: CFG.mobile, role: 'driver' });
  const v = await post('/api/v1/auth/otp/verify', { mobile: CFG.mobile, role: 'driver', code: BYPASS });
  log(`logged in — token issued, profileId=${v.user ? v.user.id : '?'}`);
  return v.token;
}

// ── 3. Connect the socket and behave like the driver app ────────────────────
function emit(socket, event, payload) {
  return new Promise((resolve) => {
    socket.emit(event, payload, (ack) => {
      if (ack && ack.ok === false) log(`  ✗ ${event}: ${ack.error} ${ack.message || ''}`);
      else log(`  ✓ ${event}`);
      resolve(ack || {});
    });
  });
}

async function runLifecycle(socket, ride) {
  // ride: { rideId, otp, pickup, drop }
  log(`ride#${ride.rideId} assigned — OTP ${ride.otp}. Running driver lifecycle…`);
  await sleep(CFG.stepMs);
  await emit(socket, 'ride:enroute', { rideId: ride.rideId });

  // nudge our position toward the pickup so the customer map moves
  if (ride.pickup) {
    for (let i = 1; i <= 3; i += 1) {
      const t = i / 4;
      await sleep(Math.round(CFG.stepMs / 3));
      await emit(socket, 'driver:location', {
        rideId: ride.rideId,
        lat: CFG.lat + (ride.pickup.lat - CFG.lat) * t,
        lng: CFG.lng + (ride.pickup.lng - CFG.lng) * t,
        bearing: 0,
        speedKmph: 24,
      });
    }
  }

  await sleep(CFG.stepMs);
  await emit(socket, 'ride:arrived', { rideId: ride.rideId });
  await sleep(CFG.stepMs);
  await emit(socket, 'ride:start', { rideId: ride.rideId, otp: ride.otp });
  await sleep(CFG.stepMs * 2);
  await emit(socket, 'ride:complete', { rideId: ride.rideId, waitingMinutes: 0 });
  log(`ride#${ride.rideId} complete — customer now settles payment in the app.`);
  log('   (once payment is settled the server frees this driver back to "available")');
}

async function goLive(token, ids) {
  const socket = io(API, { auth: { token }, transports: ['websocket'], reconnection: true });
  let busy = false;
  let hb = null;

  socket.on('connect', async () => {
    log(`socket connected (${socket.id})`);
    await emit(socket, 'driver:online', { lat: CFG.lat, lng: CFG.lng });
    log(`online at ${CFG.lat},${CFG.lng} — category ${CFG.category}, radius ${env.DISPATCH_SEARCH_RADIUS_KM}km`);
    clearInterval(hb);
    hb = setInterval(() => {
      socket.emit('driver:heartbeat', { lat: CFG.lat, lng: CFG.lng });
    }, 15_000);
    log('heartbeat every 15s — waiting for ride offers. Ctrl+C to stop.');
  });

  socket.on('connect_error', (e) => log(`connect_error: ${e.message}`));
  socket.on('disconnect', (r) => log(`socket disconnected (${r})`));

  socket.on('ride:offer', async (o) => {
    log(
      `OFFER ride#${o.rideId} — pickup ${(o.distanceToPickupM / 1000).toFixed(1)}km away, ` +
        `${o.vehicleCategory}, est ₹${o.estFare}, expires in ${o.expiresInSec}s`,
    );
    if (!AUTO_ACCEPT) return log('  (--no-accept: ignoring)');
    if (busy) return log('  already on a ride — ignoring');
    await sleep(CFG.acceptDelayMs);
    await emit(socket, 'ride:offer_response', { rideId: o.rideId, accept: true });
  });

  socket.on('ride:offer_revoked', (o) => log(`offer for ride#${o.rideId} revoked (${o.reason})`));
  socket.on('ride:cancelled', (o) => {
    log(`ride#${o.rideId} cancelled by ${o.by}`);
    busy = false;
  });

  socket.on('ride:assigned', async (a) => {
    busy = true;
    if (!AUTO_LIFECYCLE) {
      log(`ride#${a.rideId} assigned — OTP ${a.otp}. (--no-lifecycle: over to you)`);
      return;
    }
    try {
      await runLifecycle(socket, { rideId: a.rideId, otp: a.otp, pickup: a.pickup, drop: a.drop });
    } catch (e) {
      log(`lifecycle error: ${e.message}`);
    } finally {
      busy = false;
    }
  });

  const shutdown = async () => {
    log('shutting down — going offline');
    clearInterval(hb);
    try {
      await emit(socket, 'driver:offline', {});
    } catch {
      /* ignore */
    }
    socket.close();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  return socket;
}

// ── main ───────────────────────────────────────────────────────────────────
(async () => {
  log(`RedTaxi driver-sim → ${API}  (DB ${env.DB_HOST}/${env.DB_NAME})`);
  const ids = await seedProfile();
  if (SEED_ONLY) {
    log('--seed-only: done. The driver is dispatchable once it goes online (run without the flag).');
    process.exit(0);
  }
  const token = await login();
  await goLive(token, ids);
})().catch((err) => {
  console.error('\ndriver-sim failed:', err.message);
  process.exit(1);
});
