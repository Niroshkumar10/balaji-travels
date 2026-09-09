'use strict';

const db = require('../infra/db');
const { rideRef } = require('../utils/ids');
const sm = require('../services/rideStateMachine');
const ApiError = require('../utils/apiError');

const RIDE_COLS = `id, ride_ref, customer_id, driver_id, vehicle_id, status, ride_type,
  vehicle_category, pickup_lat, pickup_lng, pickup_addr, drop_lat, drop_lng, drop_addr,
  route_polyline, distance_m, duration_s, est_fare, final_fare, fare_breakdown,
  fare_config_id, promo_id, discount_amount, payment_id, payment_method, otp,
  waiting_minutes, cancelled_by, cancel_reason,
  requested_at, assigned_at, driver_arrived_at, started_at, completed_at, cancelled_at,
  created_at, updated_at`;

const rideRepo = {
  async create(data, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_rides
         (customer_id, status, ride_type, vehicle_category,
          pickup_lat, pickup_lng, pickup_addr, drop_lat, drop_lng, drop_addr,
          route_polyline, distance_m, duration_s, est_fare, fare_breakdown,
          fare_config_id, promo_id, discount_amount, payment_method)
       VALUES
         (:customerId, 'REQUESTED', :rideType, :vehicleCategory,
          :pickupLat, :pickupLng, :pickupAddr, :dropLat, :dropLng, :dropAddr,
          :routePolyline, :distanceM, :durationS, :estFare, :fareBreakdown,
          :fareConfigId, :promoId, :discountAmount, :paymentMethod)`,
      {
        customerId: data.customerId,
        rideType: data.rideType ?? 'local',
        vehicleCategory: data.vehicleCategory,
        pickupLat: data.pickupLat,
        pickupLng: data.pickupLng,
        pickupAddr: data.pickupAddr ?? null,
        dropLat: data.dropLat,
        dropLng: data.dropLng,
        dropAddr: data.dropAddr ?? null,
        routePolyline: data.routePolyline ?? null,
        distanceM: data.distanceM ?? null,
        durationS: data.durationS ?? null,
        estFare: data.estFare ?? null,
        fareBreakdown: data.fareBreakdown ? JSON.stringify(data.fareBreakdown) : null,
        fareConfigId: data.fareConfigId ?? null,
        promoId: data.promoId ?? null,
        discountAmount: data.discountAmount ?? 0,
        paymentMethod: data.paymentMethod ?? null,
      },
    );
    const id = res.insertId;
    await ctx.query(`UPDATE rt_rides SET ride_ref = :ref WHERE id = :id`, { ref: rideRef(id), id });
    return this.findById(id, ctx);
  },

  async findById(id, ctx = db) {
    return ctx.queryOne(`SELECT ${RIDE_COLS} FROM rt_rides WHERE id = :id LIMIT 1`, { id });
  },

  async findByRef(ref, ctx = db) {
    return ctx.queryOne(`SELECT ${RIDE_COLS} FROM rt_rides WHERE ride_ref = :ref LIMIT 1`, { ref });
  },

  async findActiveForCustomer(customerId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE customer_id = :customerId
          AND status NOT IN ('COMPLETED','CUSTOMER_CANCELLED','DRIVER_CANCELLED','SYSTEM_CANCELLED','NO_DRIVERS_FOUND','PAYMENT_FAILED')
        ORDER BY id DESC LIMIT 1`,
      { customerId },
    );
  },

  async findActiveForDriver(driverId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE driver_id = :driverId
          AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED','PAYMENT_PENDING')
        ORDER BY id DESC LIMIT 1`,
      { driverId },
    );
  },

  async listForCustomer(customerId, { limit = 20, offset = 0 } = {}, ctx = db) {
    return ctx.query(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE customer_id = :customerId
        ORDER BY requested_at DESC LIMIT :limit OFFSET :offset`,
      { customerId, limit: Number(limit), offset: Number(offset) },
    );
  },

  async listForDriver(driverId, { limit = 20, offset = 0 } = {}, ctx = db) {
    return ctx.query(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE driver_id = :driverId
        ORDER BY requested_at DESC LIMIT :limit OFFSET :offset`,
      { driverId, limit: Number(limit), offset: Number(offset) },
    );
  },

  /**
   * The race-safe assignment. Succeeds for AT MOST one caller: the WHERE clause
   * requires the ride to still be unclaimed, and the driver to still be free.
   * @returns {Promise<boolean>} true if THIS caller won.
   */
  async atomicAssign({ rideId, driverId, vehicleId }, ctx = db) {
    const rideUpd = await ctx.query(
      `UPDATE rt_rides
          SET driver_id = :driverId, vehicle_id = :vehicleId,
              status = 'DRIVER_ASSIGNED', assigned_at = NOW()
        WHERE id = :rideId AND status = 'SEARCHING_DRIVER' AND driver_id IS NULL`,
      { rideId, driverId, vehicleId: vehicleId ?? null },
    );
    if (rideUpd.affectedRows === 0) return false;

    const drvUpd = await ctx.query(
      `UPDATE rt_drivers SET availability = 'on_trip'
        WHERE id = :driverId AND availability = 'available'`,
      { driverId },
    );
    if (drvUpd.affectedRows === 0) {
      // driver went busy between candidate selection and now — undo the ride claim
      await ctx.query(
        `UPDATE rt_rides SET driver_id = NULL, vehicle_id = NULL,
                status = 'SEARCHING_DRIVER', assigned_at = NULL
          WHERE id = :rideId AND driver_id = :driverId`,
        { rideId, driverId },
      );
      return false;
    }

    await ctx.query(
      `INSERT INTO rt_ride_status_history (ride_id, from_status, to_status, actor, actor_id, meta)
       VALUES (:rideId, 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'system', :driverId, JSON_OBJECT('via','atomic_assign'))`,
      { rideId, driverId },
    );
    return true;
  },

  /**
   * Validated state transition. Reads the current status (locked), checks it
   * against rideStateMachine, then writes status (+ timestamp + optional cancel
   * fields) and appends history — all in the caller's transaction.
   * @returns updated ride row
   */
  async transition({ rideId, event, actorRole = 'system', actorId = null, meta = null, cancel = null }, ctx = db) {
    const cur = await ctx.queryOne(
      `SELECT id, status FROM rt_rides WHERE id = :rideId LIMIT 1 FOR UPDATE`,
      { rideId },
    );
    if (!cur) throw ApiError.notFound('Ride not found');

    sm.assertActor(event, actorRole);
    const step = sm.resolve(cur.status, event);

    const sets = ['status = :to', 'updated_at = NOW()'];
    const params = { rideId, to: step.to };
    if (step.tsField) sets.push(`${step.tsField} = NOW()`); // tsField is from the SM whitelist
    if (cancel) {
      sets.push('cancelled_by = :cancelledBy', 'cancel_reason = :cancelReason');
      params.cancelledBy = cancel.by;
      params.cancelReason = cancel.reason ?? null;
    }

    await ctx.query(`UPDATE rt_rides SET ${sets.join(', ')} WHERE id = :rideId`, params);
    await ctx.query(
      `INSERT INTO rt_ride_status_history (ride_id, from_status, to_status, actor, actor_id, meta)
       VALUES (:rideId, :from, :to, :actor, :actorId, :meta)`,
      {
        rideId,
        from: cur.status,
        to: step.to,
        actor: actorRole,
        actorId,
        meta: meta ? JSON.stringify(meta) : null,
      },
    );
    return this.findById(rideId, ctx);
  },

  async setRoute(rideId, r, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides SET route_polyline = :polyline, distance_m = :distanceM,
              duration_s = :durationS, est_fare = :estFare, fare_config_id = :fareConfigId,
              fare_breakdown = :breakdown
        WHERE id = :rideId`,
      {
        rideId,
        polyline: r.polyline ?? null,
        distanceM: r.distanceM ?? null,
        durationS: r.durationS ?? null,
        estFare: r.estFare ?? null,
        fareConfigId: r.fareConfigId ?? null,
        breakdown: r.breakdown ? JSON.stringify(r.breakdown) : null,
      },
    );
  },

  async setFinalFare(rideId, { finalFare, breakdown, discountAmount }, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides SET final_fare = :finalFare, fare_breakdown = :breakdown,
              discount_amount = COALESCE(:discountAmount, discount_amount)
        WHERE id = :rideId`,
      {
        rideId,
        finalFare,
        breakdown: breakdown ? JSON.stringify(breakdown) : null,
        discountAmount: discountAmount ?? null,
      },
    );
  },

  async setOtp(rideId, otp, ctx = db) {
    await ctx.query(`UPDATE rt_rides SET otp = :otp WHERE id = :rideId`, { rideId, otp });
  },

  async clearOtp(rideId, ctx = db) {
    await ctx.query(`UPDATE rt_rides SET otp = NULL WHERE id = :rideId`, { rideId });
  },

  async attachPayment(rideId, paymentId, method, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides SET payment_id = :paymentId, payment_method = COALESCE(:method, payment_method)
        WHERE id = :rideId`,
      { rideId, paymentId, method: method ?? null },
    );
  },

  async setWaitingMinutes(rideId, minutes, ctx = db) {
    await ctx.query(`UPDATE rt_rides SET waiting_minutes = :minutes WHERE id = :rideId`, {
      rideId,
      minutes,
    });
  },

  async history(rideId, ctx = db) {
    return ctx.query(
      `SELECT from_status, to_status, actor, actor_id, meta, created_at
         FROM rt_ride_status_history WHERE ride_id = :rideId ORDER BY id ASC`,
      { rideId },
    );
  },
};

module.exports = rideRepo;
