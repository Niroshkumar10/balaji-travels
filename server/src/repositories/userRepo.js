
'use strict';

/**
 * User identity repository.
 *
 * Two implementations, chosen by DB_DRIVER. All methods take an optional `ctx`
 * (a db-like object from withTransaction, or the memory-tx marker) so they
 * compose inside a transaction. Callers never branch on the driver.
 */

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const AUTH_FIELDS = 'id, mobile, role, name, email, status, fcm_token';

const sqlImpl = {
  findByMobileAndRole(mobile, role, ctx = db) {
    return ctx.queryOne(
      `SELECT ${AUTH_FIELDS} FROM rt_users
        WHERE mobile = :mobile AND role = :role AND deleted_at IS NULL LIMIT 1`,
      { mobile, role },
    );
  },
  findById(id, ctx = db) {
    return ctx.queryOne(`SELECT ${AUTH_FIELDS} FROM rt_users WHERE id = :id LIMIT 1`, { id });
  },
  findAuthState(id, ctx = db) {
    return ctx.queryOne(
      `SELECT id, role, status, auth_token, token_expiry FROM rt_users WHERE id = :id LIMIT 1`,
      { id },
    );
  },
  async create({ mobile, role, name = null }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_users (mobile, role, name, status) VALUES (:mobile, :role, :name, 'active')`,
      { mobile, role, name },
    );
    return res.insertId;
  },
  async setSession(userId, token, expiry, ctx = db) {
    await ctx.query(
      `UPDATE rt_users SET auth_token = :token, token_expiry = :expiry, last_active_at = NOW()
        WHERE id = :userId`,
      { userId, token, expiry },
    );
  },
  async clearSession(userId, ctx = db) {
    await ctx.query(
      `UPDATE rt_users SET auth_token = NULL, token_expiry = NULL WHERE id = :userId`,
      { userId },
    );
  },
  async setFcmToken(userId, fcmToken, ctx = db) {
    await ctx.query(`UPDATE rt_users SET fcm_token = :fcmToken WHERE id = :userId`, {
      userId,
      fcmToken,
    });
  },
  async updateProfile(userId, { name, email }, ctx = db) {
    await ctx.query(
      `UPDATE rt_users SET name = COALESCE(:name, name), email = COALESCE(:email, email)
        WHERE id = :userId`,
      { userId, name: name ?? null, email: email ?? null },
    );
  },
  async touch(userId, ctx = db) {
    await ctx.query(`UPDATE rt_users SET last_active_at = NOW() WHERE id = :userId`, { userId });
  },
};

const pick = (row, fields) =>
  row ? Object.fromEntries(fields.split(',').map((f) => f.trim()).map((f) => [f, row[f] ?? null])) : null;

const memImpl = {
  async findByMobileAndRole(mobile, role) {
    return pick(
      store.find('users', (u) => u.mobile === mobile && u.role === role && !u.deleted_at),
      AUTH_FIELDS,
    );
  },
  async findById(id) {
    return pick(store.find('users', (u) => u.id === Number(id)), AUTH_FIELDS);
  },
  async findAuthState(id) {
    const u = store.find('users', (x) => x.id === Number(id));
    return u
      ? {
          id: u.id,
          role: u.role,
          status: u.status,
          auth_token: u.auth_token ?? null,
          token_expiry: u.token_expiry ?? null,
        }
      : null;
  },
  async create({ mobile, role, name = null }) {
    return store.insert('users', {
      mobile,
      role,
      name,
      email: null,
      status: 'active',
      auth_token: null,
      token_expiry: null,
      fcm_token: null,
      last_active_at: null,
      deleted_at: null,
    }).id;
  },
  async setSession(userId, token, expiry) {
    const u = store.find('users', (x) => x.id === Number(userId));
    if (u) store.update(u, { auth_token: token, token_expiry: expiry, last_active_at: new Date().toISOString() });
  },
  async clearSession(userId) {
    const u = store.find('users', (x) => x.id === Number(userId));
    if (u) store.update(u, { auth_token: null, token_expiry: null });
  },
  async setFcmToken(userId, fcmToken) {
    const u = store.find('users', (x) => x.id === Number(userId));
    if (u) store.update(u, { fcm_token: fcmToken });
  },
  async updateProfile(userId, { name, email }) {
    const u = store.find('users', (x) => x.id === Number(userId));
    if (!u) return;
    const patch = {};
    if (name != null) patch.name = name;
    if (email != null) patch.email = email;
    store.update(u, patch);
  },
  async touch(userId) {
    const u = store.find('users', (x) => x.id === Number(userId));
    if (u) store.update(u, { last_active_at: new Date().toISOString() });
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
