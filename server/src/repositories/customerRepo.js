'use strict';

const db = require('../infra/db');
const store = require('../infra/memoryStore');

const CUSTOMER_DEFAULTS = {
  default_payment_method: 'cash',
  home_label: null,
  home_lat: null,
  home_lng: null,
  home_addr: null,
  work_label: null,
  work_lat: null,
  work_lng: null,
  work_addr: null,
};

const sqlImpl = {
  findByUserId(userId, ctx = db) {
    return ctx.queryOne(
      `SELECT id, user_id, default_payment_method,
              home_label, home_lat, home_lng, home_addr,
              work_label, work_lat, work_lng, work_addr
         FROM rt_customers WHERE user_id = :userId LIMIT 1`,
      { userId },
    );
  },
  findById(id, ctx = db) {
    return ctx.queryOne(`SELECT * FROM rt_customers WHERE id = :id LIMIT 1`, { id });
  },
  async create(userId, ctx = db) {
    const res = await ctx.query(`INSERT INTO rt_customers (user_id) VALUES (:userId)`, { userId });
    return res.insertId;
  },
  async updateProfile(id, patch, ctx = db) {
    await ctx.query(
      `UPDATE rt_customers SET
         default_payment_method = COALESCE(:defaultPaymentMethod, default_payment_method),
         home_label = COALESCE(:homeLabel, home_label),
         home_lat   = COALESCE(:homeLat, home_lat),
         home_lng   = COALESCE(:homeLng, home_lng),
         home_addr  = COALESCE(:homeAddr, home_addr),
         work_label = COALESCE(:workLabel, work_label),
         work_lat   = COALESCE(:workLat, work_lat),
         work_lng   = COALESCE(:workLng, work_lng),
         work_addr  = COALESCE(:workAddr, work_addr)
       WHERE id = :id`,
      {
        id,
        defaultPaymentMethod: patch.defaultPaymentMethod ?? null,
        homeLabel: patch.homeLabel ?? null,
        homeLat: patch.homeLat ?? null,
        homeLng: patch.homeLng ?? null,
        homeAddr: patch.homeAddr ?? null,
        workLabel: patch.workLabel ?? null,
        workLat: patch.workLat ?? null,
        workLng: patch.workLng ?? null,
        workAddr: patch.workAddr ?? null,
      },
    );
  },
};

const memImpl = {
  async findByUserId(userId) {
    return store.find('customers', (c) => c.user_id === Number(userId));
  },
  async findById(id) {
    return store.find('customers', (c) => c.id === Number(id));
  },
  async create(userId) {
    return store.insert('customers', { user_id: Number(userId), ...CUSTOMER_DEFAULTS }).id;
  },
  async updateProfile(id, patch) {
    const c = store.find('customers', (x) => x.id === Number(id));
    if (!c) return;
    const map = {
      defaultPaymentMethod: 'default_payment_method',
      homeLabel: 'home_label',
      homeLat: 'home_lat',
      homeLng: 'home_lng',
      homeAddr: 'home_addr',
      workLabel: 'work_label',
      workLat: 'work_lat',
      workLng: 'work_lng',
      workAddr: 'work_addr',
    };
    const upd = {};
    for (const [k, col] of Object.entries(map)) if (patch[k] != null) upd[col] = patch[k];
    store.update(c, upd);
  },
};

module.exports = db.MEMORY ? memImpl : sqlImpl;
