'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const fmt = (d) => new Date(d).toISOString().slice(0, 19).replace('T', ' ');

const sqlImpl = {
  async invalidateActive(mobile, role, ctx = db) {
    await ctx.query(
      `UPDATE rt_otps SET consumed_at = NOW()
        WHERE mobile = :mobile AND role = :role AND consumed_at IS NULL`,
      { mobile, role },
    );
  },
  async create({ mobile, role, codeHash, expiresAt }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_otps (mobile, role, code_hash, expires_at)
       VALUES (:mobile, :role, :codeHash, :expiresAt)`,
      { mobile, role, codeHash, expiresAt: fmt(expiresAt) },
    );
    return res.insertId;
  },
  /** Seconds since the most recent OTP was issued for (mobile, role), or null. */
  async secondsSinceLast(mobile, role, ctx = db) {
    const row = await ctx.queryOne(
      `SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) AS age
         FROM rt_otps WHERE mobile = :mobile AND role = :role
        ORDER BY id DESC LIMIT 1`,
      { mobile, role },
    );
    return row ? Number(row.age) : null;
  },
  /** Latest unconsumed challenge, row-locked for the verify transaction. */
  findLatestActive(mobile, role, ctx = db) {
    return ctx.queryOne(
      `SELECT id, code_hash, attempts, expires_at, consumed_at
         FROM rt_otps
        WHERE mobile = :mobile AND role = :role AND consumed_at IS NULL
        ORDER BY id DESC LIMIT 1
        FOR UPDATE`,
      { mobile, role },
    );
  },
  async incrementAttempts(id, ctx = db) {
    await ctx.query(`UPDATE rt_otps SET attempts = attempts + 1 WHERE id = :id`, { id });
  },
  /** Mark consumed; returns affectedRows (0 = someone else already consumed it). */
  async consume(id, ctx = db) {
    const res = await ctx.query(
      `UPDATE rt_otps SET consumed_at = NOW() WHERE id = :id AND consumed_at IS NULL`,
      { id },
    );
    return res.affectedRows;
  },
};

const memImpl = {
  async invalidateActive(mobile, role) {
    for (const o of store.filter('otps', (x) => x.mobile === mobile && x.role === role && !x.consumed_at)) {
      store.update(o, { consumed_at: new Date().toISOString() });
    }
  },
  async create({ mobile, role, codeHash, expiresAt }) {
    return store.insert('otps', {
      mobile,
      role,
      code_hash: codeHash,
      expires_at: fmt(expiresAt),
      attempts: 0,
      consumed_at: null,
      created_at: new Date().toISOString(),
    }).id;
  },
  async secondsSinceLast(mobile, role) {
    const rows = store
      .filter('otps', (x) => x.mobile === mobile && x.role === role)
      .sort((a, b) => b.id - a.id);
    if (!rows[0]?.created_at) return null;
    return Math.floor((Date.now() - new Date(rows[0].created_at).getTime()) / 1000);
  },
  async findLatestActive(mobile, role) {
    const rows = store
      .filter('otps', (x) => x.mobile === mobile && x.role === role && !x.consumed_at)
      .sort((a, b) => b.id - a.id);
    return rows[0] ?? null;
  },
  async incrementAttempts(id) {
    const o = store.find('otps', (x) => x.id === Number(id));
    if (o) store.update(o, { attempts: o.attempts + 1 });
  },
  async consume(id) {
    const o = store.find('otps', (x) => x.id === Number(id));
    if (!o || o.consumed_at) return 0;
    store.update(o, { consumed_at: new Date().toISOString() });
    return 1;
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
