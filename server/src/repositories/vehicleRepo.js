'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const FIELDS = `id, driver_id, category, make, model, plate_no, color, year,
        doc_status, rc_number, rc_expiry, rc_doc_path,
        insurance_number, insurance_expiry, insurance_doc_path,
        permit_number, permit_expiry, permit_doc_path,
        fitness_number, fitness_expiry, fitness_doc_path,
        puc_number, puc_expiry, puc_doc_path,
        is_active, created_at`;

// Whitelisted vehicle-document fields → columns — see driverRepo.DOC_COLUMNS
// for why this is a fixed table rather than building SQL from request keys.
const DOC_COLUMNS = {
  rcNumber: 'rc_number',
  rcExpiry: 'rc_expiry',
  rcDocPath: 'rc_doc_path',
  insuranceNumber: 'insurance_number',
  insuranceExpiry: 'insurance_expiry',
  insuranceDocPath: 'insurance_doc_path',
  permitNumber: 'permit_number',
  permitExpiry: 'permit_expiry',
  permitDocPath: 'permit_doc_path',
  fitnessNumber: 'fitness_number',
  fitnessExpiry: 'fitness_expiry',
  fitnessDocPath: 'fitness_doc_path',
  pucNumber: 'puc_number',
  pucExpiry: 'puc_expiry',
  pucDocPath: 'puc_doc_path',
};

const sqlImpl = {
  listByDriver(driverId, ctx = db) {
    return ctx.query(
      `SELECT ${FIELDS} FROM rt_vehicles
        WHERE driver_id = :driverId AND deleted_at IS NULL ORDER BY id DESC`,
      { driverId },
    );
  },
  findById(id, ctx = db) {
    return ctx.queryOne(`SELECT ${FIELDS} FROM rt_vehicles WHERE id = :id LIMIT 1`, { id });
  },
  async create(driverId, v, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_vehicles (driver_id, category, make, model, plate_no, color, year)
       VALUES (:driverId, :category, :make, :model, :plateNo, :color, :year)`,
      {
        driverId,
        category: v.category,
        make: v.make ?? null,
        model: v.model ?? null,
        plateNo: v.plateNo,
        color: v.color ?? null,
        year: v.year ?? null,
      },
    );
    return res.insertId;
  },
  async setActiveForDriver(driverId, vehicleId, ctx = db) {
    await ctx.query(
      `UPDATE rt_vehicles SET is_active = IF(id = :vehicleId, 1, 0) WHERE driver_id = :driverId`,
      { driverId, vehicleId },
    );
    await ctx.query(`UPDATE rt_drivers SET current_vehicle_id = :vehicleId WHERE id = :driverId`, {
      driverId,
      vehicleId,
    });
  },

  /**
   * Writes a vehicle document submission (RC / insurance / permit / fitness /
   * PUC) — only columns present in `patch` are touched. A new/changed
   * document resets doc_status to 'pending' for re-review, same rationale as
   * driverRepo.updateDocuments.
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
    sets.push(`doc_status = 'pending'`);
    await ctx.query(`UPDATE rt_vehicles SET ${sets.join(', ')} WHERE id = :id`, params);
  },
};

const memImpl = {
  async listByDriver(driverId) {
    return store
      .filter('vehicles', (v) => v.driver_id === Number(driverId) && !v.deleted_at)
      .sort((a, b) => b.id - a.id);
  },
  async findById(id) {
    return store.find('vehicles', (v) => v.id === Number(id));
  },
  async create(driverId, v) {
    return store.insert('vehicles', {
      driver_id: Number(driverId),
      category: v.category,
      make: v.make ?? null,
      model: v.model ?? null,
      plate_no: v.plateNo,
      color: v.color ?? null,
      year: v.year ?? null,
      doc_status: 'pending',
      is_active: 1,
      deleted_at: null,
    }).id;
  },
  async setActiveForDriver(driverId, vehicleId) {
    for (const v of store.filter('vehicles', (x) => x.driver_id === Number(driverId))) {
      store.update(v, { is_active: v.id === Number(vehicleId) ? 1 : 0 });
    }
    const d = store.find('drivers', (x) => x.id === Number(driverId));
    if (d) store.update(d, { current_vehicle_id: Number(vehicleId) });
  },
  async updateDocuments(id, patch) {
    const v = store.find('vehicles', (x) => x.id === Number(id));
    if (!v) return;
    const changes = {};
    for (const [key, col] of Object.entries(DOC_COLUMNS)) {
      if (patch[key] !== undefined) changes[col] = patch[key];
    }
    if (Object.keys(changes).length === 0) return;
    store.update(v, { ...changes, doc_status: 'pending' });
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
