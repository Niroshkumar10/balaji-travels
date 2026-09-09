'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const FIELDS = `id, driver_id, category, make, model, plate_no, color, year,
        doc_status, is_active, created_at`;

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
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
