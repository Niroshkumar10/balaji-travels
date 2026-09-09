'use strict';

const db = require('../infra/db');

const savedPlaceRepo = {
  list(customerId, ctx = db) {
    return ctx.query(
      `SELECT id, label, lat, lng, addr, created_at FROM rt_saved_places
        WHERE customer_id = :customerId ORDER BY id DESC`,
      { customerId },
    );
  },
  async create(customerId, { label, lat, lng, addr }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_saved_places (customer_id, label, lat, lng, addr)
       VALUES (:customerId, :label, :lat, :lng, :addr)`,
      { customerId, label, lat, lng, addr: addr ?? null },
    );
    return res.insertId;
  },
  async remove(customerId, id, ctx = db) {
    const res = await ctx.query(
      `DELETE FROM rt_saved_places WHERE id = :id AND customer_id = :customerId`,
      { id, customerId },
    );
    return res.affectedRows > 0;
  },
};

module.exports = savedPlaceRepo;
