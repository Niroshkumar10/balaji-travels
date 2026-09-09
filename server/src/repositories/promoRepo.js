'use strict';

const db = require('../infra/db');

const promoRepo = {
  findByCode(code, ctx = db) {
    return ctx.queryOne(`SELECT * FROM rt_promos WHERE code = :code LIMIT 1`, {
      code: String(code).toUpperCase(),
    });
  },

  redemptionsForUser(promoId, userId, ctx = db) {
    return ctx
      .queryOne(
        `SELECT COUNT(*) AS n FROM rt_promo_redemptions WHERE promo_id = :promoId AND user_id = :userId`,
        { promoId, userId },
      )
      .then((r) => Number(r?.n ?? 0));
  },

  async redeem(ctx, { promoId, userId, rideId, discount }) {
    await ctx.query(
      `INSERT INTO rt_promo_redemptions (promo_id, user_id, ride_id, discount)
       VALUES (:promoId, :userId, :rideId, :discount)`,
      { promoId, userId, rideId, discount },
    );
    await ctx.query(`UPDATE rt_promos SET used_count = used_count + 1 WHERE id = :promoId`, {
      promoId,
    });
  },

  list(ctx = db) {
    return ctx.query(`SELECT * FROM rt_promos ORDER BY id DESC`);
  },
};

module.exports = promoRepo;
