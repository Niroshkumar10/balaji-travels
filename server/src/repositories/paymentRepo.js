'use strict';

const db = require('../infra/db');
const { paymentRef } = require('../utils/ids');

const COLS = `id, payment_ref, ride_id, customer_id, method, amount, currency, status,
  gateway, gateway_order_id, gateway_payment_id, idempotency_key, attempts,
  failure_reason, paid_at, created_at, updated_at`;

const paymentRepo = {
  async create({ rideId, customerId, method, amount, gateway, idempotencyKey }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_payments (ride_id, customer_id, method, amount, gateway, idempotency_key, status)
       VALUES (:rideId, :customerId, :method, :amount, :gateway, :idempotencyKey, 'pending')`,
      { rideId, customerId, method, amount, gateway: gateway ?? null, idempotencyKey: idempotencyKey ?? null },
    );
    const id = res.insertId;
    await ctx.query(`UPDATE rt_payments SET payment_ref = :ref WHERE id = :id`, {
      ref: paymentRef(id),
      id,
    });
    return this.findById(id, ctx);
  },

  findById(id, ctx = db) {
    return ctx.queryOne(`SELECT ${COLS} FROM rt_payments WHERE id = :id LIMIT 1`, { id });
  },

  findByIdempotencyKey(key, ctx = db) {
    return ctx.queryOne(`SELECT ${COLS} FROM rt_payments WHERE idempotency_key = :key LIMIT 1`, {
      key,
    });
  },

  /** Latest payment attempt for a ride. */
  findLatestForRide(rideId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${COLS} FROM rt_payments WHERE ride_id = :rideId ORDER BY id DESC LIMIT 1`,
      { rideId },
    );
  },

  findPaidForRide(rideId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${COLS} FROM rt_payments WHERE ride_id = :rideId AND status = 'paid' LIMIT 1`,
      { rideId },
    );
  },

  async setGatewayOrder(id, orderId, ctx = db) {
    await ctx.query(`UPDATE rt_payments SET gateway_order_id = :orderId WHERE id = :id`, {
      id,
      orderId,
    });
  },

  /**
   * Mark paid. Relies on the UNIQUE(paid_ride_id) storage guard: if another
   * row for this ride is already 'paid', this UPDATE throws ER_DUP_ENTRY and
   * the caller treats it as "already settled".
   */
  async markPaid(id, { gatewayPaymentId } = {}, ctx = db) {
    await ctx.query(
      `UPDATE rt_payments
          SET status = 'paid', paid_at = NOW(), attempts = attempts + 1,
              gateway_payment_id = COALESCE(:gwPid, gateway_payment_id)
        WHERE id = :id AND status <> 'paid'`,
      { id, gwPid: gatewayPaymentId ?? null },
    );
  },

  async markFailed(id, reason, ctx = db) {
    await ctx.query(
      `UPDATE rt_payments SET status = 'failed', failure_reason = :reason, attempts = attempts + 1
        WHERE id = :id AND status NOT IN ('paid','refunded')`,
      { id, reason: reason ?? null },
    );
  },

  async reopen(id, ctx = db) {
    await ctx.query(
      `UPDATE rt_payments SET status = 'pending', failure_reason = NULL WHERE id = :id AND status = 'failed'`,
      { id },
    );
  },

  // ── webhook idempotency ──
  async recordEvent({ paymentId, eventId, eventType, payload }, ctx = db) {
    try {
      await ctx.query(
        `INSERT INTO rt_payment_events (payment_id, event_id, event_type, payload)
         VALUES (:paymentId, :eventId, :eventType, :payload)`,
        {
          paymentId: paymentId ?? null,
          eventId,
          eventType: eventType ?? null,
          payload: payload ? JSON.stringify(payload) : null,
        },
      );
      return true; // first time we've seen this event
    } catch (err) {
      if (err.code === 'ER_DUP_ENTRY') return false; // replay — already handled
      throw err;
    }
  },

  async markEventProcessed(eventId, ctx = db) {
    await ctx.query(
      `UPDATE rt_payment_events SET processed_at = NOW() WHERE event_id = :eventId`,
      { eventId },
    );
  },
};

module.exports = paymentRepo;
