'use strict';

/**
 * Dummy OTP flow demo — runs the REAL auth + profile code end to end with
 * DB_DRIVER=memory (no MySQL, no Redis, no SMS gateway). Prints every request
 * and response so the whole login lifecycle is visible.
 *
 *   node scripts/demo-otp-flow.js
 *   (or)  npm run demo:otp
 *
 * "Dummy" = the OTP is never sent by SMS; in non-production the code is
 * returned in the /auth/otp/request response as `devCode` and also logged by
 * the console SMS provider. That is the only shortcut — every other step
 * (hashing, FOR-UPDATE-style single-use consume, JWT + live-token session,
 * find-or-create profile, single-active-session revocation) is the real path.
 */

// Configure the in-memory / no-secret-file environment BEFORE anything loads.
// NODE_ENV=test keeps the logger silent so the demo's own output is readable;
// it does not change any auth behaviour and devCode is still returned (non-prod).
process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'memory';
process.env.SMS_PROVIDER = 'console';
process.env.FIREBASE_SERVICE_ACCOUNT_PATH = '';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'demo-only-secret-key-not-for-real-use-1234567890';
process.env.ADMIN_HMAC_SECRET = process.env.ADMIN_HMAC_SECRET || 'demo-admin-hmac-secret';
process.env.PORT = process.env.PORT || '4599';

const http = require('http');
const createApp = require('../src/app');

const BASE = `http://127.0.0.1:${process.env.PORT}`;
let step = 0;

function hr() {
  console.log('─'.repeat(72));
}

async function call(method, path, { token, body } = {}) {
  step += 1;
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  console.log(`\n${step}.  ${method} ${path}   →  ${res.status}`);
  if (body) console.log(`    request : ${JSON.stringify(body)}`);
  console.log(`    response: ${JSON.stringify(json)}`);
  return { status: res.status, json };
}

async function main() {
  const app = createApp();
  const server = http.createServer(app);
  await new Promise((r) => server.listen(Number(process.env.PORT), r));
  console.log(`RedTaxi demo server (DB_DRIVER=memory) on ${BASE}`);

  // ─────────────────────────────────────────────────────────────────────────
  hr();
  console.log('A.  CUSTOMER — request OTP, verify, use session');
  hr();

  const mobile = '9876500011';

  const req1 = await call('POST', '/api/v1/auth/otp/request', {
    body: { mobile, role: 'customer' },
  });
  const devCode = req1.json.devCode;
  console.log(`\n    ↑ the "dummy" OTP is ${devCode} (returned only because NODE_ENV!=production)`);

  await call('POST', '/api/v1/auth/otp/verify', {
    body: { mobile, role: 'customer', code: '0000' },
  }).then((r) => console.log(`    ↑ wrong code rejected as expected (${r.json.error?.code})`));

  const verify = await call('POST', '/api/v1/auth/otp/verify', {
    body: { mobile, role: 'customer', code: devCode },
  });
  const custToken = verify.json.token;
  console.log(`\n    ↑ login ok — isNewUser=${verify.json.isNewUser}, token issued`);

  await call('GET', '/api/v1/auth/me', { token: custToken });
  await call('GET', '/api/v1/customers/me', { token: custToken });
  await call('PATCH', '/api/v1/customers/me', {
    token: custToken,
    body: { name: 'Asha R', homeLabel: 'Home', homeLat: 12.9611, homeLng: 77.6387, homeAddr: 'Indiranagar' },
  });

  // ─────────────────────────────────────────────────────────────────────────
  hr();
  console.log('B.  SINGLE ACTIVE SESSION — a new login revokes the old token');
  hr();

  const req2 = await call('POST', '/api/v1/auth/otp/request', { body: { mobile, role: 'customer' } });
  const verify2 = await call('POST', '/api/v1/auth/otp/verify', {
    body: { mobile, role: 'customer', code: req2.json.devCode },
  });
  const custToken2 = verify2.json.token;

  await call('GET', '/api/v1/customers/me', { token: custToken }).then((r) =>
    console.log(`    ↑ OLD token now rejected: ${r.status} ${r.json.error?.code}`),
  );
  await call('GET', '/api/v1/customers/me', { token: custToken2 }).then((r) =>
    console.log(`    ↑ NEW token works: ${r.status}`),
  );

  // ─────────────────────────────────────────────────────────────────────────
  hr();
  console.log('C.  DRIVER — separate identity on the same number, add a vehicle');
  hr();

  const dReq = await call('POST', '/api/v1/auth/otp/request', { body: { mobile, role: 'driver' } });
  const dVerify = await call('POST', '/api/v1/auth/otp/verify', {
    body: { mobile, role: 'driver', code: dReq.json.devCode },
  });
  const driverToken = dVerify.json.token;

  await call('POST', '/api/v1/drivers/me/vehicle', {
    token: driverToken,
    body: { category: 'sedan', make: 'Maruti', model: 'Dzire', plateNo: 'KA01AB1234', color: 'White' },
  });
  await call('GET', '/api/v1/drivers/me', { token: driverToken });

  await call('GET', '/api/v1/drivers/me', { token: custToken2 }).then((r) =>
    console.log(`    ↑ customer token blocked from driver route: ${r.status} ${r.json.error?.code}`),
  );

  // ─────────────────────────────────────────────────────────────────────────
  hr();
  console.log('D.  CONCURRENCY — 5 parallel verifies of one code → exactly one wins');
  hr();

  const cMobile = '9876500022';
  const cReq = await call('POST', '/api/v1/auth/otp/request', { body: { mobile: cMobile, role: 'customer' } });
  const code = cReq.json.devCode;

  const results = await Promise.all(
    Array.from({ length: 5 }, () =>
      fetch(`${BASE}/api/v1/auth/otp/verify`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ mobile: cMobile, role: 'customer', code }),
      }).then((r) => r.status),
    ),
  );
  const wins = results.filter((s) => s === 200).length;
  console.log(`\n    statuses: ${JSON.stringify(results)}`);
  console.log(`    winners (200): ${wins}   ${wins === 1 ? '✓ exactly one' : '✗ EXPECTED 1'}`);

  // ─────────────────────────────────────────────────────────────────────────
  hr();
  console.log('E.  LOGOUT');
  hr();
  await call('POST', '/api/v1/auth/logout', { token: driverToken });
  await call('GET', '/api/v1/drivers/me', { token: driverToken }).then((r) =>
    console.log(`    ↑ token after logout: ${r.status} ${r.json.error?.code}`),
  );

  hr();
  console.log('demo complete');
  server.close();
  process.exit(wins === 1 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
