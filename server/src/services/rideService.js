'use strict';

const db = require('../infra/db');
const logger = require('../infra/logger');
const ApiError = require('../utils/apiError');
const geo = require('./geoService');
const fareService = require('./fareService');
const promoService = require('./promoService');
const dispatchService = require('./dispatchService');
const paymentService = require('./paymentService');
const notifyService = require('./notifyService');
const rentalService = require('./rentalService');
const realtime = require('../realtime/emitter');
const rideRepo = require('../repositories/rideRepo');
const customerRepo = require('../repositories/customerRepo');
const driverRepo = require('../repositories/driverRepo');
const vehicleRepo = require('../repositories/vehicleRepo');
const userRepo = require('../repositories/userRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');

const ALL_CATEGORIES = ['bike', 'auto', 'hatchback', 'sedan', 'suv'];
const maskPhone = (m) => (m ? `${m.slice(0, 2)}xxxxx${m.slice(-3)}` : null);

// Fallback only — every ride's duration_s is set at creation (real route
// duration for local/outstation/round_trip, hours*3600 for rental), so this
// should never actually be hit in practice.
const DEFAULT_RIDE_DURATION_S = 2 * 60 * 60;

// db.js's pool is configured `timezone: 'Z'` + `dateStrings: true` — every
// DATETIME comes back as a plain "YYYY-MM-DD HH:mm:ss" string that IS a UTC
// instant but carries no marker saying so. `new Date()` on a string like
// that parses it as LOCAL time, which silently shifts it by the server's
// UTC offset (5:30 in IST) — wrong instant, and specifically wrong in the
// direction that makes two genuinely-overlapping windows look like they
// don't overlap. Existing/requested timestamps read back from the DB MUST
// go through this, not a bare `new Date(...)`; scheduledAt from an incoming
// request is already a real Date/ISO string (via zod's z.coerce.date()) and
// is exempt — only round-tripped DB strings have this problem.
function parseDbTimestampUtc(s) {
  if (!s) return null;
  return s instanceof Date ? s : new Date(`${String(s).replace(' ', 'T')}Z`);
}

/** [start, end) epoch-ms window a ride occupies, for conflict checking. */
function rideWindow(startMs, durationS) {
  const start = startMs;
  const end = start + (durationS ?? DEFAULT_RIDE_DURATION_S) * 1000;
  return { start, end };
}

const windowsOverlap = (a, b) => a.start < b.end && b.start < a.end;

/**
 * Booking-conflict check — replaces the old blanket "one active ride, any
 * type" rule with two narrower ones:
 *
 *   1. Local vs local is still a hard, status-based block (no time math):
 *      any non-terminal local ride blocks a new immediate local booking,
 *      UNLESS the existing one is itself just a future-scheduled local ride
 *      still sitting at REQUESTED (not yet dispatched) — that one falls
 *      through to rule 2 like any other future booking. Status, not a
 *      duration estimate, is what decides this: a real trip can run longer
 *      than its quoted duration_s (traffic, etc.), and only the ride's
 *      actual status can't drift out of sync with that.
 *
 *   2. Everything else (local-vs-non-local, non-local-vs-non-local, and a
 *      future-scheduled local) is a time-window overlap check: each ride
 *      occupies [scheduled_at ?? requested_at, that + duration_s], and two
 *      overlapping windows conflict regardless of ride_type. This is what
 *      lets "rental tomorrow" and "local today" coexist, and blocks two
 *      future bookings whose pickup times actually collide.
 *
 * @param {Array} existingRides  rideRepo.listActiveForCustomer() rows
 * @param {{rideType:string, scheduledAt:(Date|string|null), durationS:number}} newRide
 */
function assertNoBookingConflict(existingRides, newRide) {
  const newStart = newRide.scheduledAt ? new Date(newRide.scheduledAt).getTime() : Date.now();
  const newWindow = rideWindow(newStart, newRide.durationS);

  for (const existing of existingRides) {
    if (newRide.rideType === 'local' && existing.ride_type === 'local') {
      const existingIsFutureScheduled =
        existing.status === 'REQUESTED' &&
        existing.scheduled_at &&
        parseDbTimestampUtc(existing.scheduled_at).getTime() > Date.now();
      if (!existingIsFutureScheduled) {
        throw ApiError.conflict('You already have an active local ride', 'HAS_ACTIVE_RIDE', {
          rideId: existing.id,
          status: existing.status,
        });
      }
      // else: a local ride scheduled for later — fall through to rule 2.
    }

    const existingStart = existing.scheduled_at
      ? parseDbTimestampUtc(existing.scheduled_at).getTime()
      : parseDbTimestampUtc(existing.requested_at).getTime();
    const existingWindow = rideWindow(existingStart, existing.duration_s);

    if (windowsOverlap(existingWindow, newWindow)) {
      throw ApiError.conflict('This booking conflicts with the timing of another ride you already have', 'BOOKING_TIME_CONFLICT', {
        rideId: existing.id,
        status: existing.status,
      });
    }
  }
}

async function enrich(ride) {
  if (!ride) return null;
  const out = { ...ride };
  if (ride.fare_breakdown && typeof ride.fare_breakdown === 'string') {
    try {
      out.fare_breakdown = JSON.parse(ride.fare_breakdown);
    } catch {
      /* leave as-is */
    }
  }
  if (ride.driver_id) {
    const [driver, vehicle, loc] = await Promise.all([
      driverRepo.findById(ride.driver_id),
      ride.vehicle_id ? vehicleRepo.findById(ride.vehicle_id) : null,
      driverLocationRepo.get(ride.driver_id),
    ]);
    const dUser = driver ? await userRepo.findById(driver.user_id) : null;
    out.driver = driver
      ? {
          id: driver.id,
          name: dUser?.name ?? 'Driver',
          rating: Number(driver.rating_avg),
          phoneMasked: maskPhone(dUser?.mobile),
        }
      : null;
    out.vehicle = vehicle
      ? {
          category: vehicle.category,
          plateNo: vehicle.plate_no,
          make: vehicle.make,
          model: vehicle.model,
          color: vehicle.color,
        }
      : null;
    out.driverLocation = loc
      ? { lat: Number(loc.lat), lng: Number(loc.lng), bearing: loc.bearing, updatedAt: loc.updated_at }
      : null;
  }
  return out;
}

function assertOwnership(ride, requester) {
  const owns =
    (requester.role === 'customer' && ride.customer_id === requester.profileId) ||
    (requester.role === 'driver' && ride.driver_id === requester.profileId);
  if (!owns) throw ApiError.forbidden('Not your ride', 'RIDE_FORBIDDEN');
}

const rideService = {
  async estimate({ pickup, drop, categories }) {
    const route = await geo.route(pickup, drop);
    const cats = (categories && categories.length ? categories : ALL_CATEGORIES).filter((c) =>
      ALL_CATEGORIES.includes(c),
    );
    const options = [];
    for (const category of cats) {
      try {
        const q = await fareService.quote({
          category,
          distanceM: route.distanceM,
          durationS: route.durationS,
        });
        options.push({ category, fare: q.total, currency: q.currency, breakdown: q.breakdown });
      } catch (err) {
        logger.debug({ err: err.message, category }, 'estimate: no config for category');
      }
    }
    return {
      route: {
        distanceM: route.distanceM,
        durationS: route.durationS,
        polyline: route.polyline,
        source: route.source,
      },
      options,
    };
  },

  async createRide({
    customer,
    pickup,
    drop,
    vehicleCategory,
    rideType = 'local',
    paymentMethod = 'cash',
    promoCode,
    bookingSource = 'app',
    createdByAdminId = null,
    // { orderId, paymentId, signature } — required when paymentMethod is
    // 'upi'. The customer already paid the quoted fare via Razorpay BEFORE
    // calling this (see paymentService.createPrebookOrder) — verified here,
    // before anything is created, so a driver can never be offered a ride
    // for a payment that failed, was cancelled, or was never made.
    payment,
    // Required when rideType is 'rental' — one of rentalService.PACKAGE_HOURS.
    rentalPackageHours,
    // Optional on any ride type — a future pickup time. When it's more than
    // a couple of minutes out, dispatch is held back instead of starting
    // immediately; jobs/scheduledDispatch.js starts it (via the exact same
    // dispatchService.start() below) once that time arrives.
    scheduledAt,
  }) {
    if (paymentMethod === 'upi') {
      if (!payment?.orderId || !payment?.paymentId) {
        throw ApiError.badRequest('Payment confirmation required for UPI bookings', 'PAYMENT_REQUIRED');
      }
      // Throws on a bad/missing signature — nothing below has run yet, so no
      // ride and no dispatch are ever created for an unverified payment.
      paymentService.verifyPrebookSignature(payment);
    }

    // geo.route() still runs for every ride type — the map/polyline is still
    // worth showing even for a rental, whose FARE is not distance-based.
    const route = await geo.route(pickup, drop);

    // Rental: fare comes from the fixed package (hours + included km) the
    // customer picked on the package-selection screen, quoted fresh here via
    // the exact same fareService.quote() every other ride uses — never the
    // real pickup→drop route distance, and never a client-supplied amount.
    const isRental = rideType === 'rental';
    let packageQuote = null;
    if (isRental) {
      packageQuote = await rentalService.quoteOnePackage({ category: vehicleCategory, hours: rentalPackageHours });
    }
    const rideDistanceM = isRental ? packageQuote.distanceM : route.distanceM;
    const rideDurationS = isRental ? packageQuote.durationS : route.durationS;

    const existingRides = await rideRepo.listActiveForCustomer(customer.profileId);
    assertNoBookingConflict(existingRides, { rideType, scheduledAt, durationS: rideDurationS });

    let quote = isRental
      ? packageQuote
      : await fareService.quote({
          category: vehicleCategory,
          distanceM: rideDistanceM,
          durationS: rideDurationS,
        });

    let promoId = null;
    let discountAmount = 0;
    if (promoCode) {
      const p = await promoService.validate({
        code: promoCode,
        userId: customer.userId,
        fare: quote.total,
      });
      promoId = p.promoId;
      discountAmount = p.discount;
      quote = await fareService.quote({
        category: vehicleCategory,
        distanceM: rideDistanceM,
        durationS: rideDurationS,
        promoDiscount: discountAmount,
      });
    }

    const ride = await rideRepo.create({
      customerId: customer.profileId,
      rideType,
      vehicleCategory,
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      pickupAddr: pickup.addr ?? null,
      dropLat: drop.lat,
      dropLng: drop.lng,
      dropAddr: drop.addr ?? null,
      routePolyline: route.polyline,
      distanceM: rideDistanceM,
      durationS: rideDurationS,
      estFare: quote.total,
      fareBreakdown: quote.breakdown,
      fareConfigId: quote.config_id,
      promoId,
      discountAmount,
      paymentMethod,
      bookingSource,
      createdByAdminId,
      rentalPackageHours: isRental ? rentalPackageHours : null,
      scheduledAt: scheduledAt ?? null,
    });

    if (paymentMethod === 'upi') {
      await paymentService.recordPrebookPayment({
        rideId: ride.id,
        customerId: customer.profileId,
        amount: quote.total,
        orderId: payment.orderId,
        paymentId: payment.paymentId,
      });
    }

    // Local: a ride scheduled more than a couple of minutes out stays at
    // REQUESTED (its normal first status) — jobs/scheduledDispatch.js calls
    // this exact same dispatchService.start() once the time is close,
    // instead of a second dispatch path. Anything sooner (or no schedule at
    // all) behaves exactly as before: dispatch starts immediately.
    //
    // Outstation/round_trip/rental: never auto-dispatched, scheduled or not.
    // These stay at REQUESTED indefinitely — the external Admin Panel picks
    // them up and assigns a driver directly (rt_rides.driver_id + status),
    // the same mechanism it already uses for its own call-in bookings. See
    // jobs/adminBookingAnnouncer.js, which watches for exactly that and
    // backfills the OTP/route/notifications a normal dispatch accept would
    // otherwise have produced.
    const holdForLater = scheduledAt && new Date(scheduledAt).getTime() - Date.now() > 2 * 60 * 1000;
    if (rideType === 'local' && !holdForLater) {
      dispatchService.start(ride).catch((err) => logger.error({ err, rideId: ride.id }, 'dispatch start failed'));
    }
    return enrich(await rideRepo.findById(ride.id));
  },

  async getRide(rideId, requester) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    assertOwnership(ride, requester);
    return enrich(ride);
  },

  async getActiveRide(requester) {
    const ride =
      requester.role === 'customer'
        ? await rideRepo.findActiveForCustomer(requester.profileId)
        : await rideRepo.findActiveForDriver(requester.profileId);
    return ride ? enrich(ride) : null;
  },

  async listRides(requester, opts) {
    const rows =
      requester.role === 'customer'
        ? await rideRepo.listForCustomer(requester.profileId, opts)
        : await rideRepo.listForDriver(requester.profileId, opts);
    return rows;
  },

  async history(rideId, requester) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    assertOwnership(ride, requester);
    return rideRepo.history(rideId);
  },

  async cancelRide(rideId, requester, reason) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    assertOwnership(ride, requester);

    const event = requester.role === 'customer' ? 'cancel_customer' : 'cancel_driver';
    const updated = await db.withTransaction(async (tx) => {
      const r = await rideRepo.transition(
        {
          rideId,
          event,
          actorRole: requester.role,
          actorId: requester.profileId,
          meta: { reason },
          cancel: { by: requester.role, reason },
        },
        tx,
      );
      if (ride.driver_id) await driverRepo.freeFromTrip(ride.driver_id, tx);
      return r;
    });

    if (ride.status === 'SEARCHING_DRIVER' || ride.status === 'REQUESTED') {
      dispatchService.cancelDispatch(rideId);
    }

    // notify the other party
    const customer = await customerRepo.findById(ride.customer_id);
    if (requester.role === 'customer' && ride.driver_id) {
      const drv = await driverRepo.findById(ride.driver_id);
      realtime.toUser(drv.user_id, 'ride:cancelled', { rideId, by: 'customer', reason });
      notifyService.notify(drv.user_id, {
        type: 'ride_cancelled',
        title: 'Ride cancelled',
        body: 'The customer cancelled the ride.',
        data: { rideId: String(rideId) },
      });
    }
    if (requester.role === 'driver') {
      realtime.toUser(customer.user_id, 'ride:cancelled', { rideId, by: 'driver', reason });
      notifyService.notify(customer.user_id, {
        type: 'ride_cancelled',
        title: 'Driver cancelled',
        body: 'Your driver cancelled. Please book again.',
        data: { rideId: String(rideId) },
      });
    }
    return enrich(updated);
  },

  // ── driver intents ──────────────────────────────────────────────────────────
  async _driverEvent(rideId, driverProfileId, event, { meta, extra } = {}) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (ride.driver_id !== driverProfileId) throw ApiError.forbidden('Not your ride', 'RIDE_FORBIDDEN');
    const updated = await db.withTransaction((tx) =>
      rideRepo.transition({ rideId, event, actorRole: 'driver', actorId: driverProfileId, meta }, tx),
    );
    const customer = await customerRepo.findById(ride.customer_id);
    realtime.toUser(customer.user_id, 'ride:status', {
      rideId,
      status: updated.status,
      ...(extra ?? {}),
    });
    return { ride: updated, customerUserId: customer.user_id };
  },

  async driverEnroute(rideId, driverProfileId) {
    // "en_route" status-location: last-known position, never invented — see
    // driverLocationRepo.getRecentMeta. A stale/missing GPS never blocks the
    // transition itself, it just means this one gets no location stamped.
    const meta = await driverLocationRepo.getRecentMeta(driverProfileId);
    const { ride } = await this._driverEvent(rideId, driverProfileId, 'driver_enroute', { meta });
    return enrich(ride);
  },

  async driverArrived(rideId, driverProfileId) {
    const meta = await driverLocationRepo.getRecentMeta(driverProfileId);
    const { ride, customerUserId } = await this._driverEvent(rideId, driverProfileId, 'driver_arrived', { meta });
    realtime.toUser(customerUserId, 'ride:driver_arrived', { rideId });
    notifyService.notify(customerUserId, {
      type: 'driver_arrived',
      title: 'Driver has arrived',
      body: 'Your driver is waiting at the pickup point.',
      data: { rideId: String(rideId) },
    });
    return enrich(ride);
  },

  async startRide(rideId, driverProfileId, otp) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (ride.driver_id !== driverProfileId) throw ApiError.forbidden();
    if (!ride.otp || String(otp) !== String(ride.otp)) {
      throw ApiError.badRequest('Incorrect OTP', 'BAD_RIDE_OTP');
    }
    const updated = await db.withTransaction(async (tx) => {
      const r = await rideRepo.transition(
        { rideId, event: 'start_ride', actorRole: 'driver', actorId: driverProfileId },
        tx,
      );
      await rideRepo.clearOtp(rideId, tx);
      return r;
    });
    const customer = await customerRepo.findById(ride.customer_id);
    realtime.toUser(customer.user_id, 'ride:started', { rideId, status: updated.status });
    notifyService.notify(customer.user_id, {
      type: 'ride_started',
      title: 'Ride started',
      body: 'Enjoy your ride!',
      data: { rideId: String(rideId) },
    });
    return enrich(updated);
  },

  async completeRide(rideId, driverProfileId, { waitingMinutes = 0 } = {}) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    if (ride.driver_id !== driverProfileId) throw ApiError.forbidden();

    const finalQuote = await fareService.quote({
      category: ride.vehicle_category,
      distanceM: ride.distance_m,
      durationS: ride.duration_s,
      waitingMin: waitingMinutes,
      promoDiscount: Number(ride.discount_amount ?? 0),
    });

    // "completed" status-location — captured here (drop-off), not later at
    // payment settlement, since that can happen well after/away from the
    // actual trip end.
    const meta = await driverLocationRepo.getRecentMeta(driverProfileId);

    const completed = await db.withTransaction(async (tx) => {
      await rideRepo.transition(
        { rideId, event: 'complete', actorRole: 'driver', actorId: driverProfileId, meta }, tx,
      );
      await rideRepo.setFinalFare(rideId, { finalFare: finalQuote.total, breakdown: finalQuote.breakdown }, tx);
      await rideRepo.setWaitingMinutes(rideId, waitingMinutes, tx);
      return rideRepo.transition({ rideId, event: 'to_payment', actorRole: 'system' }, tx);
    });

    // make sure a payment row exists for the chosen method
    const { settled } = await paymentService.ensureForRide(rideId, { method: completed.payment_method });

    // A pre-booked UPI ride was already paid in full before dispatch even
    // started (see createRide()) — ensureForRide() just found that existing
    // 'paid' row instead of creating a new pending one. Nothing else will
    // ever call "confirm payment" for it, so close the loop right here the
    // same way settleCash()/verifyClientPayment() do, instead of leaving the
    // ride stuck at PAYMENT_PENDING and telling an already-paid customer an
    // amount is still due.
    if (settled) {
      const result = await paymentService.settleAlreadyPaid(rideId);
      return enrich(result.ride);
    }

    const customer = await customerRepo.findById(ride.customer_id);
    const drv = await driverRepo.findById(ride.driver_id);
    const payload = {
      rideId,
      status: completed.status,
      finalFare: finalQuote.total,
      breakdown: finalQuote.breakdown,
      paymentMethod: completed.payment_method,
    };
    realtime.toUser(customer.user_id, 'ride:driver_completed', payload);
    realtime.toUser(drv.user_id, 'ride:driver_completed', payload);
    realtime.toUser(customer.user_id, 'ride:payment_pending', payload);
    notifyService.notify(customer.user_id, {
      type: 'payment_pending',
      title: 'Ride finished',
      body: `Amount due ₹${finalQuote.total} (${completed.payment_method}).`,
      data: { rideId: String(rideId) },
    });

    return enrich(completed);
  },

  /** Rebuild the authoritative snapshot after a client reconnects. */
  async resync(rideId, requester) {
    return this.getRide(rideId, requester);
  },
};

module.exports = rideService;
