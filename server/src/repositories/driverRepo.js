'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const DRIVER_SELECT = `d.id, d.user_id, d.kyc_status, d.kyc_reject_reason, d.license_no,
        d.license_expiry, d.license_doc_path, d.id_proof_type, d.id_proof_number,
        d.id_proof_doc_path, d.photo_path,
        d.rating_avg, d.rating_count, d.is_online, d.availability,
        d.current_vehicle_id, d.last_seen_at`;

// Whitelisted driver-document fields → columns. Never build SQL from raw
// request keys — this table is the only thing that decides what can be
// written, same pattern as driverRepo.updateProfile's fixed COALESCE list.
const DOC_COLUMNS = {
  licenseNo: 'license_no',
  licenseExpiry: 'license_expiry',
  licenseDocPath: 'license_doc_path',
  idProofType: 'id_proof_type',
  idProofNumber: 'id_proof_number',
  idProofDocPath: 'id_proof_doc_path',
  photoPath: 'photo_path',
};

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
  async create(userId, { name, mobile } = {}, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_drivers (user_id, name, mobile, kyc_status, availability)
       VALUES (:userId, :name, :mobile, 'pending', 'offline')`,
      { userId, name: name ?? null, mobile: mobile ?? null },
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

  /**
   * Writes a driver document submission (license / ID proof / photo) — only
   * columns present in `patch` are touched. Submitting a new/changed document
   * puts KYC back to 'pending' so an admin reviews it again, same as a fresh
   * application; it never flips a review verdict on its own.
   */
  async updateDocuments(id, patch, ctx = db) {
    const sets = [];
    const params = { id };
    for (const [key, col] of Object.entries(DOC_COLUMNS)) {
      if (patch[key] === undefined) continue;
      sets.push(`${col} = :${key}`);
      params[key] = patch[key];
    }
    if (sets.length === 0) return;
    sets.push(`kyc_status = 'pending'`, `kyc_reviewed_by = NULL`, `kyc_reviewed_at = NULL`, `kyc_reject_reason = NULL`);
    await ctx.query(`UPDATE rt_drivers SET ${sets.join(', ')} WHERE id = :id`, params);
  },
};

const memImpl = {
  async findByUserId(userId) {
    return store.find('drivers', (d) => d.user_id === Number(userId));
  },
  async findById(id) {
    return store.find('drivers', (d) => d.id === Number(id));
  },
  async create(userId, { name, mobile } = {}) {
    const d = store.insert('drivers', {
      user_id: Number(userId),
      name: name ?? null,
      mobile: mobile ?? null,
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
  async updateDocuments(id, patch) {
    const d = store.find('drivers', (x) => x.id === Number(id));
    if (!d) return;
    const changes = {};
    for (const [key, col] of Object.entries(DOC_COLUMNS)) {
      if (patch[key] !== undefined) changes[col] = patch[key];
    }
    if (Object.keys(changes).length === 0) return;
    store.update(d, { ...changes, kyc_status: 'pending', kyc_reviewed_by: null, kyc_reviewed_at: null, kyc_reject_reason: null });
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
