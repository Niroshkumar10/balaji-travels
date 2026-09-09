'use strict';

const db = require('../infra/db');
const ApiError = require('../utils/apiError');

/**
 * Double-entry-ish wallet. Every balance change writes a ledger row with the
 * post-change balance snapshot, in the same transaction, so the ledger always
 * reconciles to rt_driver_wallet.balance.
 */
const walletRepo = {
  async ensure(driverId, ctx = db) {
    await ctx.query(
      `INSERT INTO rt_driver_wallet (driver_id, balance) VALUES (:driverId, 0)
       ON DUPLICATE KEY UPDATE driver_id = driver_id`,
      { driverId },
    );
  },

  getBalance(driverId, ctx = db) {
    return ctx
      .queryOne(`SELECT balance FROM rt_driver_wallet WHERE driver_id = :driverId`, { driverId })
      .then((r) => Number(r?.balance ?? 0));
  },

  /**
   * Apply a signed amount. MUST be called inside a transaction. Locks the
   * wallet row, computes the new balance, appends the ledger entry.
   * @returns {Promise<number>} new balance
   */
  async apply(ctx, driverId, { rideId = null, type, amount, ref = null, note = null }) {
    if (!ctx || ctx === db) throw ApiError.internal('walletRepo.apply must run in a transaction');
    await this.ensure(driverId, ctx);
    const row = await ctx.queryOne(
      `SELECT balance FROM rt_driver_wallet WHERE driver_id = :driverId FOR UPDATE`,
      { driverId },
    );
    const current = Number(row.balance);
    const next = Math.round((current + Number(amount)) * 100) / 100;
    if (next < 0) throw ApiError.badRequest('Insufficient wallet balance', 'INSUFFICIENT_BALANCE');

    await ctx.query(`UPDATE rt_driver_wallet SET balance = :next WHERE driver_id = :driverId`, {
      next,
      driverId,
    });
    await ctx.query(
      `INSERT INTO rt_wallet_ledger (driver_id, ride_id, type, amount, balance_after, ref, note)
       VALUES (:driverId, :rideId, :type, :amount, :next, :ref, :note)`,
      { driverId, rideId, type, amount, next, ref, note },
    );
    return next;
  },

  ledger(driverId, { limit = 30, offset = 0 } = {}, ctx = db) {
    return ctx.query(
      `SELECT id, ride_id, type, amount, balance_after, ref, note, created_at
         FROM rt_wallet_ledger WHERE driver_id = :driverId
        ORDER BY id DESC LIMIT :limit OFFSET :offset`,
      { driverId, limit: Number(limit), offset: Number(offset) },
    );
  },

  async summary(driverId, sinceSql, ctx = db) {
    return ctx.queryOne(
      `SELECT
         COALESCE(SUM(CASE WHEN type = 'trip_earning' THEN amount ELSE 0 END), 0) AS gross,
         COALESCE(SUM(CASE WHEN type = 'commission'   THEN amount ELSE 0 END), 0) AS commission,
         COALESCE(SUM(CASE WHEN type = 'incentive'    THEN amount ELSE 0 END), 0) AS incentives,
         COALESCE(SUM(CASE WHEN type = 'payout'       THEN -amount ELSE 0 END), 0) AS paid_out,
         COUNT(DISTINCT CASE WHEN type = 'trip_earning' THEN ride_id END) AS trips
       FROM rt_wallet_ledger
       WHERE driver_id = :driverId ${sinceSql ? 'AND created_at >= :since' : ''}`,
      sinceSql ? { driverId, since: sinceSql } : { driverId },
    );
  },

  async createPayout(ctx, driverId, amount) {
    const res = await ctx.query(
      `INSERT INTO rt_payouts (driver_id, amount, status) VALUES (:driverId, :amount, 'requested')`,
      { driverId, amount },
    );
    return res.insertId;
  },

  listPayouts(driverId, ctx = db) {
    return ctx.query(
      `SELECT id, amount, status, gateway_ref, requested_at, processed_at
         FROM rt_payouts WHERE driver_id = :driverId ORDER BY id DESC LIMIT 50`,
      { driverId },
    );
  },
};

module.exports = walletRepo;
