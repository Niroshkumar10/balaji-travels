'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const DRIVER_SELECT = `d.id, d.user_id, d.kyc_status, d.license_no,
        d.rating_avg, d.rating_count, d.is_online, d.availability,
        d.current_vehicle_id, d.last_seen_at`;

const sqlImpl = {
  findByUserId(userId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${DRIVER_SELECT} FROM rt_drivers d WHERE d.user_id = :userId LIMIT 1`,
      { userId },
    );
  },
  findById(id, ctx = db) {
    return ctx.queryOne(`SELECT * FROM rt_drivers WHERE id = :id LIMIT 1`, { id });
  },
  async create(userId, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_drivers (user_id, kyc_status, availability) VALUES (:userId, 'pending', 'offline')`,
      { userId },
    );
    await ctx.query(`INSERT INTO rt_driver_wallet (driver_id, balance) VALUES (:id, 0)`, {
      id: res.insertId,
    });
    return res.insertId;
  },
  async updateProfile(id, patch, ctx = db) {
    await ctx.query(
      `UPDATE rt_drivers SET license_no = COALESCE(:licenseNo, license_no) WHERE id = :id`,
      { id, licenseNo: patch.licenseNo ?? null },
    );
  },
  async setPresence(id, { isOnline, availability }, ctx = db) {
    await ctx.query(
      `UPDATE rt_drivers SET is_online = :isOnline, availability = :availability, last_seen_at = NOW()
        WHERE id = :id`,
      { id, isOnline: isOnline ? 1 : 0, availability },
    );
  },
  async touchLastSeen(id, ctx = db) {
    await ctx.query(`UPDATE rt_drivers SET last_seen_at = NOW() WHERE id = :id`, { id });
  },

  /** Return an on_trip driver to the available pool once a ride ends/cancels. */
  async freeFromTrip(id, ctx = db) {
    await ctx.query(
      `UPDATE rt_drivers SET availability = 'available'
        WHERE id = :id AND availability = 'on_trip' AND is_online = 1`,
      { id },
    );
  },

  async updateRating(id, { avg, count }, ctx = db) {
    await ctx.query(
      `UPDATE rt_drivers SET rating_avg = :avg, rating_count = :count WHERE id = :id`,
      { id, avg, count },
    );
  },

  async setKyc(id, { status, reviewerId, reason }, ctx = db) {
    await ctx.query(
      `UPDATE rt_drivers
          SET kyc_status = :status, kyc_reviewed_by = :reviewerId,
              kyc_reviewed_at = NOW(), kyc_reject_reason = :reason
        WHERE id = :id`,
      { id, status, reviewerId: reviewerId ?? null, reason: reason ?? null },
    );
  },
};

const memImpl = {
  async findByUserId(userId) {
    return store.find('drivers', (d) => d.user_id === Number(userId));
  },
  async findById(id) {
    return store.find('drivers', (d) => d.id === Number(id));
  },
  async create(userId) {
    const d = store.insert('drivers', {
      user_id: Number(userId),
      kyc_status: 'pending',
      kyc_reviewed_by: null,
      kyc_reviewed_at: null,
      kyc_reject_reason: null,
      license_no: null,
      rating_avg: 0,
      rating_count: 0,
      is_online: 0,
      availability: 'offline',
      current_vehicle_id: null,
      last_seen_at: null,
    });
    store.insert('driver_wallet', { driver_id: d.id, balance: 0 });
    return d.id;
  },
  async updateProfile(id, patch) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d && patch.licenseNo != null) store.update(d, { license_no: patch.licenseNo });
  },
  async setPresence(id, { isOnline, availability }) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d) store.update(d, { is_online: isOnline ? 1 : 0, availability, last_seen_at: new Date().toISOString() });
  },
  async touchLastSeen(id) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d) store.update(d, { last_seen_at: new Date().toISOString() });
  },
  async freeFromTrip(id) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d && d.availability === 'on_trip' && d.is_online === 1) store.update(d, { availability: 'available' });
  },
  async updateRating(id, { avg, count }) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d) store.update(d, { rating_avg: avg, rating_count: count });
  },
  async setKyc(id, { status, reviewerId, reason }) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (d) store.update(d, { kyc_status: status, kyc_reviewed_by: reviewerId ?? null, kyc_reviewed_at: new Date().toISOString(), kyc_reject_reason: reason ?? null });
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
