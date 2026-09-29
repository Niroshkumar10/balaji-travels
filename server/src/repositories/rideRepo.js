'use strict';

const db = require('../infra/db');
const { rideRef } = require('../utils/ids');
const sm = require('../services/rideStateMachine');
const ApiError = require('../utils/apiError');
const { windowsOverlap, windowForRideRow } = require('../utils/rideWindow');

const RIDE_COLS = `id, ride_ref, customer_id, driver_id, vehicle_id, status, ride_type,
  vehicle_category, pickup_lat, pickup_lng, pickup_addr, drop_lat, drop_lng, drop_addr,
  route_polyline, distance_m, duration_s, est_fare, final_fare, fare_breakdown,
  fare_config_id, promo_id, discount_amount, payment_id, payment_method, otp,
  waiting_minutes, cancelled_by, cancel_reason, scheduled_at, rental_package_hours,
  requested_at, assigned_at, driver_accepted_at, driver_accepted_by,
  driver_arrived_at, started_at, completed_at, cancelled_at,
  created_at, updated_at`;

// Statuses where a driver "holds" a ride — either actually driving it, or
// reserved on an accepted, not-yet-started non-local booking. Reuses
// rideStateMachine's DRIVER_ACTIVE (same set) as the single source of
// truth rather than duplicating the literal list here.
const DRIVER_HELD_STATUSES = [...sm.DRIVER_ACTIVE];

const rideRepo = {
  async create(data, ctx = db) {
    // bookingSource/createdByAdminId/scheduledAt/rentalPackageHours default
    // to today's behaviour (column default 'app' / NULL) — every existing
    // caller that doesn't pass them is completely unaffected.
    const res = await ctx.query(
      `INSERT INTO rt_rides
         (customer_id, status, ride_type, vehicle_category,
          pickup_lat, pickup_lng, pickup_addr, drop_lat, drop_lng, drop_addr,
          route_polyline, distance_m, duration_s, est_fare, fare_breakdown,
          fare_config_id, promo_id, discount_amount, payment_method,
          booking_source, created_by_admin_id, scheduled_at, rental_package_hours)
       VALUES
         (:customerId, 'REQUESTED', :rideType, :vehicleCategory,
          :pickupLat, :pickupLng, :pickupAddr, :dropLat, :dropLng, :dropAddr,
          :routePolyline, :distanceM, :durationS, :estFare, :fareBreakdown,
          :fareConfigId, :promoId, :discountAmount, :paymentMethod,
          :bookingSource, :createdByAdminId, :scheduledAt, :rentalPackageHours)`,
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
        bookingSource: data.bookingSource ?? 'app',
        createdByAdminId: data.createdByAdminId ?? null,
        scheduledAt: data.scheduledAt ?? null,
        rentalPackageHours: data.rentalPackageHours ?? null,
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

  /**
   * EVERY non-terminal ride for this customer (not just the latest one) —
   * a customer can legitimately hold several at once now (e.g. a rental
   * scheduled for tomorrow AND a local ride today), so the booking-conflict
   * check in rideService.createRide() needs the full set to test each one,
   * not just whichever is most recent. Kept separate from
   * findActiveForCustomer() above, which single-ride callers (the "resume
   * ride" banner, GET /rides/active) still rely on unchanged.
   */
  async listActiveForCustomer(customerId, ctx = db) {
    return ctx.query(
      `SELECT id, ride_type, status, scheduled_at, requested_at, duration_s
         FROM rt_rides
        WHERE customer_id = :customerId
          AND status NOT IN ('COMPLETED','CUSTOMER_CANCELLED','DRIVER_CANCELLED','SYSTEM_CANCELLED','NO_DRIVERS_FOUND','PAYMENT_FAILED')`,
      { customerId },
    );
  },

  /**
   * Same non-terminal set as listActiveForCustomer(), but full ride rows —
   * for the customer home screen, which now shows one card per concurrent
   * active ride (one per service type) instead of a single "resume ride"
   * banner. See rideService.listActiveRides().
   */
  async findAllActiveForCustomer(customerId, ctx = db) {
    return ctx.query(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE customer_id = :customerId
          AND status NOT IN ('COMPLETED','CUSTOMER_CANCELLED','DRIVER_CANCELLED','SYSTEM_CANCELLED','NO_DRIVERS_FOUND','PAYMENT_FAILED')
        ORDER BY id DESC`,
      { customerId },
    );
  },

  /**
   * The ONE ride currently occupying the driver's exclusive active_driver_id
   * slot — i.e. what they're actually, physically driving right now. A
   * reserved-but-not-yet-navigating booking never appears here (see
   * migration 0004); use listHeldForDriver()/findAllHeldForDriver() for the
   * broader set that also includes reservations.
   */
  async findActiveForDriver(driverId, ctx = db) {
    return ctx.queryOne(
      `SELECT ${RIDE_COLS} FROM rt_rides WHERE active_driver_id = :driverId LIMIT 1`,
      { driverId },
    );
  },

  /**
   * Every ride this driver currently HOLDS — driving now, or reserved on an
   * accepted future non-local booking. Used for time-window conflict checks
   * (a driver can't be offered/accept something that overlaps ANY of these),
   * not just their single live ride. See DRIVER_HELD_STATUSES above.
   */
  async listHeldForDriver(driverId, { excludeRideId } = {}, ctx = db) {
    return ctx.query(
      `SELECT id, ride_type, status, scheduled_at, requested_at, duration_s, driver_accepted_at
         FROM rt_rides
        WHERE driver_id = :driverId
          AND status IN (${DRIVER_HELD_STATUSES.map((s) => `'${s}'`).join(',')})
          ${excludeRideId ? 'AND id != :excludeRideId' : ''}`,
      excludeRideId ? { driverId, excludeRideId } : { driverId },
    );
  },

  /** Bulk variant of listHeldForDriver(), grouped by driver_id — for candidatesForAdmin(). */
  async listHeldForDrivers(driverIds, ctx = db) {
    if (!driverIds.length) return [];
    return ctx.query(
      `SELECT driver_id, id, ride_type, status, scheduled_at, requested_at, duration_s, driver_accepted_at
         FROM rt_rides
        WHERE driver_id IN (:driverIds)
          AND status IN (${DRIVER_HELD_STATUSES.map((s) => `'${s}'`).join(',')})`,
      { driverIds },
    );
  },

  /**
   * Mirrors migration 0004's active_driver_id CASE exactly — true if this
   * held-ride row is the one currently occupying the driver's exclusive
   * slot (actually live right now), false if it's merely a reserved,
   * not-yet-started hold. Kept here (not in rideWindow.js) since it's a
   * status predicate, not a time-window one.
   */
  isLiveHold(row) {
    if (['DRIVER_ARRIVING', 'DRIVER_ARRIVED', 'RIDE_STARTED', 'RIDE_IN_PROGRESS', 'DRIVER_COMPLETED', 'PAYMENT_PENDING'].includes(row.status)) return true;
    return row.status === 'DRIVER_ASSIGNED' && row.ride_type === 'local';
  },

  /**
   * Every ride a driver holds (see above), full rows — for the driver's
   * "Rental and Trip" screen (rideService.listActiveRides() driver branch).
   */
  async findAllHeldForDriver(driverId, ctx = db) {
    return ctx.query(
      `SELECT ${RIDE_COLS} FROM rt_rides
        WHERE driver_id = :driverId
          AND status IN (${DRIVER_HELD_STATUSES.map((s) => `'${s}'`).join(',')})
        ORDER BY COALESCE(scheduled_at, requested_at) ASC`,
      { driverId },
    );
  },

  /**
   * Throws BOOKING_TIME_CONFLICT-style if `window` overlaps anything this
   * driver already holds (excludeRideId lets a ride check against its OWN
   * prior hold safely, e.g. re-accepting). Reuses utils/rideWindow.js's
   * overlap math — the same logic already used for the customer-side
   * booking conflict check and the admin-candidate time filter.
   */
  async assertNoHoldConflict({ driverId, window, excludeRideId }, ctx = db) {
    const held = await this.listHeldForDriver(driverId, { excludeRideId }, ctx);
    const conflict = held.find((r) => windowsOverlap(windowForRideRow(r), window));
    if (conflict) {
      throw ApiError.conflict(
        'This booking overlaps another ride this driver already holds',
        'RESERVATION_TIME_CONFLICT',
        { rideId: conflict.id },
      );
    }
  },

  /** Records the driver's explicit acceptance of an admin-assigned booking. */
  async markDriverAccepted(rideId, driverId, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides SET driver_accepted_at = NOW(), driver_accepted_by = :driverId
        WHERE id = :rideId AND driver_id = :driverId`,
      { rideId, driverId },
    );
  },

  /**
   * Undoes an admin assignment (driver declined, or the accept gate needs
   * to hand the ride back). Mirrors atomicAssign()'s own rollback SQL, plus
   * clears the acceptance columns and any OTP already backfilled for the
   * declining driver — the next driver assigned needs a fresh one.
   */
  async clearAssignment(rideId, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides
          SET driver_id = NULL, vehicle_id = NULL, assigned_at = NULL,
              driver_accepted_at = NULL, driver_accepted_by = NULL, otp = NULL
        WHERE id = :rideId`,
      { rideId },
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
  async atomicAssign({ rideId, driverId, vehicleId, lat, lng }, ctx = db) {
    let rideUpd;
    try {
      rideUpd = await ctx.query(
        `UPDATE rt_rides
            SET driver_id = :driverId, vehicle_id = :vehicleId,
                status = 'DRIVER_ASSIGNED', assigned_at = NOW()
          WHERE id = :rideId AND status = 'SEARCHING_DRIVER' AND driver_id IS NULL`,
        { rideId, driverId, vehicleId: vehicleId ?? null },
      );
    } catch (err) {
      // Local-only: the driver is mid-claim on a DIFFERENT ride right now
      // (active_driver_id's unique slot is taken) — a genuine lost race,
      // not an error. See migration 0004's redefinition of active_driver_id.
      if (err.code === 'ER_DUP_ENTRY') return false;
      throw err;
    }
    if (rideUpd.affectedRows === 0) return false;

    // 'reserved' is claimable here too — a driver already reserved on a
    // future non-local booking can still accept a Local (or a further
    // non-overlapping admin pick; the caller re-verifies non-overlap via
    // assertNoHoldConflict before ever reaching this point for that case).
    // This briefly sets 'on_trip' unconditionally; the caller corrects it
    // to 'reserved' via driverRepo.recomputeAvailability() in the same
    // transaction when the ride being claimed isn't actually live yet.
    const drvUpd = await ctx.query(
      `UPDATE rt_drivers SET availability = 'on_trip'
        WHERE id = :driverId AND availability IN ('available','reserved')`,
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

    // "accepted" status-location: the candidate's lat/lng is already on hand
    // from the dispatch nearby-query that selected them (see dispatchService's
    // handleOfferResponse) — never a fake/invented value, and never a fresh
    // query, since it's what dispatch itself just used to offer this driver.
    const meta = { via: 'atomic_assign' };
    if (lat != null && lng != null) {
      meta.latitude = Number(lat);
      meta.longitude = Number(lng);
    }
    await ctx.query(
      `INSERT INTO rt_ride_status_history (ride_id, from_status, to_status, actor, actor_id, meta)
       VALUES (:rideId, 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'system', :driverId, :meta)`,
      { rideId, driverId, meta: JSON.stringify(meta) },
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

  async setRoute(rideId, { polyline, distanceM, durationS }, ctx = db) {
    await ctx.query(
      `UPDATE rt_rides SET route_polyline = :polyline, distance_m = :distanceM, duration_s = :durationS
        WHERE id = :rideId`,
      { rideId, polyline: polyline ?? null, distanceM, durationS },
    );
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
