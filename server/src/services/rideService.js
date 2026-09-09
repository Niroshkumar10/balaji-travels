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
const realtime = require('../realtime/emitter');
const rideRepo = require('../repositories/rideRepo');
const customerRepo = require('../repositories/customerRepo');
const driverRepo = require('../repositories/driverRepo');
const vehicleRepo = require('../repositories/vehicleRepo');
const userRepo = require('../repositories/userRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');

const ALL_CATEGORIES = ['bike', 'auto', 'hatchback', 'sedan', 'suv'];
const maskPhone = (m) => (m ? `${m.slice(0, 2)}xxxxx${m.slice(-3)}` : null);

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

  async createRide({ customer, pickup, drop, vehicleCategory, rideType = 'local', paymentMethod = 'cash', promoCode }) {
    const active = await rideRepo.findActiveForCustomer(customer.profileId);
    if (active) {
      throw ApiError.conflict('You already have an active ride', 'HAS_ACTIVE_RIDE', {
        rideId: active.id,
        status: active.status,
      });
    }

    const route = await geo.route(pickup, drop);
    let quote = await fareService.quote({
      category: vehicleCategory,
      distanceM: route.distanceM,
      durationS: route.durationS,
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
        distanceM: route.distanceM,
        durationS: route.durationS,
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
      distanceM: route.distanceM,
      durationS: route.durationS,
      estFare: quote.total,
      fareBreakdown: quote.breakdown,
      fareConfigId: quote.config_id,
      promoId,
      discountAmount,
      paymentMethod,
    });

    dispatchService.start(ride).catch((err) => logger.error({ err, rideId: ride.id }, 'dispatch start failed'));
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
    const { ride } = await this._driverEvent(rideId, driverProfileId, 'driver_enroute');
    return enrich(ride);
  },

  async driverArrived(rideId, driverProfileId) {
    const { ride, customerUserId } = await this._driverEvent(rideId, driverProfileId, 'driver_arrived');
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

    const completed = await db.withTransaction(async (tx) => {
      await rideRepo.transition(
        { rideId, event: 'complete', actorRole: 'driver', actorId: driverProfileId }, tx,
      );
      await rideRepo.setFinalFare(rideId, { finalFare: finalQuote.total, breakdown: finalQuote.breakdown }, tx);
      await rideRepo.setWaitingMinutes(rideId, waitingMinutes, tx);
      return rideRepo.transition({ rideId, event: 'to_payment', actorRole: 'system' }, tx);
    });

    // make sure a payment row exists for the chosen method
    await paymentService.ensureForRide(rideId, { method: completed.payment_method });

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
