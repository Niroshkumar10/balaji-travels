'use strict';

const request = require('supertest');
const createApp = require('../../src/app');
const store = require('../../src/infra/memoryStore');

const app = createApp();
const api = () => request(app);

async function login(mobile, role) {
  const req = await api().post('/api/v1/auth/otp/request').send({ mobile, role });
  const code = req.body.devCode;
  const verify = await api().post('/api/v1/auth/otp/verify').send({ mobile, role, code });
  return { token: verify.body.token, body: verify.body, code };
}

beforeEach(() => store.reset());

describe('OTP request', () => {
  it('issues a code and returns devCode in non-production', async () => {
    const res = await api().post('/api/v1/auth/otp/request').send({ mobile: '9876543210', role: 'customer' });
    expect(res.status).toBe(200);
    expect(res.body.sent).toBe(true);
    expect(res.body.devCode).toMatch(/^\d{4}$/);
  });

  it('rejects a malformed mobile number', async () => {
    const res = await api().post('/api/v1/auth/otp/request').send({ mobile: '12345', role: 'customer' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects an unknown role', async () => {
    const res = await api().post('/api/v1/auth/otp/request').send({ mobile: '9876543210', role: 'admin' });
    expect(res.status).toBe(400);
  });

  it('normalises +91 / leading 0 prefixes', async () => {
    const res = await api().post('/api/v1/auth/otp/request').send({ mobile: '+919876543210', role: 'driver' });
    expect(res.status).toBe(200);
  });
});

describe('OTP verify', () => {
  it('creates a customer + profile on first successful verify', async () => {
    const { body } = await login('9811111111', 'customer');
    expect(body.token).toBeTruthy();
    expect(body.isNewUser).toBe(true);
    expect(body.user).toMatchObject({ mobile: '9811111111', role: 'customer' });
    expect(body.profile.default_payment_method).toBe('cash');
  });

  it('rejects an incorrect code and increments attempts', async () => {
    await api().post('/api/v1/auth/otp/request').send({ mobile: '9822222222', role: 'customer' });
    const res = await api()
      .post('/api/v1/auth/otp/verify')
      .send({ mobile: '9822222222', role: 'customer', code: '0000' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('OTP_INVALID');
  });

  it('locks after 5 wrong attempts', async () => {
    await api().post('/api/v1/auth/otp/request').send({ mobile: '9833333333', role: 'customer' });
    for (let i = 0; i < 5; i++) {
      await api().post('/api/v1/auth/otp/verify').send({ mobile: '9833333333', role: 'customer', code: '0001' });
    }
    const res = await api()
      .post('/api/v1/auth/otp/verify')
      .send({ mobile: '9833333333', role: 'customer', code: '0001' });
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe('OTP_LOCKED');
  });

  it('a code cannot be reused', async () => {
    const { code } = await login('9844444444', 'customer');
    const res = await api()
      .post('/api/v1/auth/otp/verify')
      .send({ mobile: '9844444444', role: 'customer', code });
    expect(res.status).toBe(400);
    expect(['OTP_NOT_FOUND', 'OTP_CONSUMED']).toContain(res.body.error.code);
  });

  it('same number can hold separate customer and driver identities', async () => {
    const c = await login('9855555555', 'customer');
    const d = await login('9855555555', 'driver');
    expect(c.body.user.id).not.toBe(d.body.user.id);
    expect(d.body.profile.kyc_status).toBe('pending');
  });
});

describe('single active session', () => {
  it('a new login revokes the previous token', async () => {
    const first = await login('9866666666', 'customer');
    const okBefore = await api().get('/api/v1/customers/me').set('Authorization', `Bearer ${first.token}`);
    expect(okBefore.status).toBe(200);

    const second = await login('9866666666', 'customer');
    const oldAfter = await api().get('/api/v1/customers/me').set('Authorization', `Bearer ${first.token}`);
    const newAfter = await api().get('/api/v1/customers/me').set('Authorization', `Bearer ${second.token}`);

    expect(oldAfter.status).toBe(401);
    expect(oldAfter.body.error.code).toBe('SESSION_SUPERSEDED');
    expect(newAfter.status).toBe(200);
  });

  it('logout invalidates the token', async () => {
    const { token } = await login('9877777777', 'customer');
    await api().post('/api/v1/auth/logout').set('Authorization', `Bearer ${token}`).expect(200);
    const after = await api().get('/api/v1/customers/me').set('Authorization', `Bearer ${token}`);
    expect(after.status).toBe(401);
  });
});

describe('role isolation', () => {
  it('a customer token cannot reach a driver route', async () => {
    const { token } = await login('9888888888', 'customer');
    const res = await api().get('/api/v1/drivers/me').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('WRONG_ROLE');
  });

  it('unauthenticated requests are rejected', async () => {
    await api().get('/api/v1/customers/me').expect(401);
    await api().get('/api/v1/drivers/me').expect(401);
  });
});

describe('concurrent verify — exactly one winner', () => {
  it('5 parallel verifies of one code yield a single session', async () => {
    const mobile = '9899999999';
    const req = await api().post('/api/v1/auth/otp/request').send({ mobile, role: 'customer' });
    const code = req.body.devCode;

    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        api().post('/api/v1/auth/otp/verify').send({ mobile, role: 'customer', code }),
      ),
    );
    const wins = results.filter((r) => r.status === 200);
    expect(wins).toHaveLength(1);
    // and only one user row was created
    expect(store.tables.users.filter((u) => u.mobile === mobile)).toHaveLength(1);
  });
});

describe('profile updates', () => {
  it('customer can patch name + saved places', async () => {
    const { token } = await login('9810000001', 'customer');
    const res = await api()
      .patch('/api/v1/customers/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Ravi K', homeLat: 12.9, homeLng: 77.6, homeLabel: 'Home' });
    expect(res.status).toBe(200);
    expect(res.body.profile.name).toBe('Ravi K');
    expect(res.body.profile.customer.home_label).toBe('Home');
  });

  it('driver can add a vehicle and it becomes active', async () => {
    const { token } = await login('9810000002', 'driver');
    const add = await api()
      .post('/api/v1/drivers/me/vehicle')
      .set('Authorization', `Bearer ${token}`)
      .send({ category: 'auto', plateNo: 'ka05cd6789', make: 'Bajaj' });
    expect(add.status).toBe(201);
    expect(add.body.vehicle.plate_no).toBe('KA05CD6789');

    const me = await api().get('/api/v1/drivers/me').set('Authorization', `Bearer ${token}`);
    expect(me.body.profile.vehicles).toHaveLength(1);
    expect(me.body.profile.driver.current_vehicle_id).toBe(add.body.vehicle.id);
  });

  it('rejects unknown fields on profile patch (strict schema)', async () => {
    const { token } = await login('9810000003', 'customer');
    const res = await api()
      .patch('/api/v1/customers/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ role: 'admin' });
    expect(res.status).toBe(400);
  });
});
