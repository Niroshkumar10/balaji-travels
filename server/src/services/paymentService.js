'use strict';

/**
 * Payments — server-validated and idempotent by construction.
 *
 *   • amount always = ride.final_fare (never a client-supplied number)
 *   • one row per attempt; retried "create" with the same Idempotency-Key
 *     returns the same row
 *   • settlement relies on the UNIQUE(paid_ride_id) storage guard — a second
 *     "mark paid" for the same ride throws and is treated as already-settled
 *   • webhooks are deduped on the gateway event id (rt_payment_events)
 *
 * Razorpay is used via its REST API (no SDK dep). With no keys configured the
 * gateway path degrades to a local stub so the flow still runs in dev.
 */

const crypto = require('crypto');
const env = require('../config/env');
const logger = require('../infra/logger');
const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const realtime = require('../realtime/emitter');
const notifyService = require('./notifyService');
const earningsService = require('./earningsService');
const promoService = require('./promoService');
const geo = require('./geoService');
const fareService = require('./fareService');
const paymentRepo = require('../repositories/paymentRepo');
const rideRepo = require('../repositories/rideRepo');
const driverRepo = require('../repositories/driverRepo');
const customerRepo = require('../repositories/customerRepo');

const GATEWAY_METHODS = new Set(['upi', 'card']);
const hasRazorpay = Boolean(env.RAZORPAY_KEY_ID && env.RAZORPAY_KEY_SECRET);

function hmacHex(secret, data) {
  return crypto.createHmac('sha256', secret).update(data).digest('hex');
}

/**
 * Same check verifyClientPayment always did — extracted so the pre-booking
 * UPI flow (pay BEFORE the ride/dispatch exists — see rideService.createRide)
 * can use the exact same verification, not a second implementation of it.
 * No keys configured (dev/sandbox) → nothing to check against, matches the
 * existing verifyClientPayment behavior of skipping verification then too.
 */
function isValidSignature(orderId, paymentId, signature) {
  if (!hasRazorpay) return true;
  const expected = hmacHex(env.RAZORPAY_KEY_SECRET, `${orderId}|${paymentId}`);
  try {
    return Boolean(signature) && crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
  } catch {
    return false; // e.g. length mismatch — timingSafeEqual throws instead of returning false
  }
}

async function createRazorpayOrder(amountPaise, receipt) {
  if (!hasRazorpay) {
    return { id: `order_stub_${crypto.randomBytes(8).toString('hex')}`, amount: amountPaise, currency: 'INR', stub: true };
  }
  const auth = Buffer.from(`${env.RAZORPAY_KEY_ID}:${env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount: amountPaise, currency: 'INR', receipt }),
  });
  if (!res.ok) {
    const body = await res.text();
    logger.error({ status: res.status, body }, 'razorpay order create failed');
    throw ApiError.internal('Payment gateway error', 'GATEWAY_ERROR');
  }
  return res.json();
}

/** Shared settlement: mark paid → advance ride → credit driver → free driver. */
async function settlePaidRide(tx, { rideId, paymentId, gatewayPaymentId }) {
  const ride = await rideRepo.findById(rideId, tx);
  if (!ride) throw ApiError.notFound('Ride not found');

  if (ride.status === 'COMPLETED') return { ride, alreadySettled: true };
  if (ride.status !== 'PAYMENT_PENDING' && ride.status !== 'PAYMENT_FAILED') {
    throw ApiError.conflict(`Ride not awaiting payment (status ${ride.status})`, 'RIDE_NOT_PAYABLE');
  }

  try {
    await paymentRepo.markPaid(paymentId, { gatewayPaymentId }, tx);
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return { ride, alreadySettled: true }; // paid_ride_id guard
    throw err;
  }

  if (ride.status === 'PAYMENT_FAILED') {
    await rideRepo.transition({ rideId, event: 'payment_retry', actorRole: 'system' }, tx);
  }
  const completed = await rideRepo.transition({ rideId, event: 'payment_ok', actorRole: 'system' }, tx);
  await rideRepo.attachPayment(rideId, paymentId, null, tx);

  if (ride.driver_id) {
    await earningsService.creditRide(tx, ride.driver_id, completed);
    await driverRepo.freeFromTrip(ride.driver_id, tx);
  }

  // Record the promo redemption now — only a genuinely paid ride consumes it,
  // so a cancelled/abandoned ride never burns the customer's allowance.
  if (completed.promo_id && Number(completed.discount_amount) > 0) {
    try {
      const cust = await customerRepo.findById(completed.customer_id, tx);
      await promoService.redeem(tx, {
        promoId: completed.promo_id,
        userId: cust.user_id,
        rideId: completed.id,
        discount: Number(completed.discount_amount),
      });
    } catch (err) {
      if (err.code !== 'ER_DUP_ENTRY') throw err; // already recorded — fine
    }
  }
  return { ride: completed, alreadySettled: false };
}

async function emitSettled(ride) {
  const customer = await customerRepo.findById(ride.customer_id);
  const driver = ride.driver_id ? await driverRepo.findById(ride.driver_id) : null;
  const payload = { rideId: ride.id, status: ride.status, amount: ride.final_fare, paymentStatus: 'paid' };
  if (customer) {
    realtime.toUser(customer.user_id, 'ride:payment_update', payload);
    realtime.toUser(customer.user_id, 'ride:completed', payload);
    notifyService.notify(customer.user_id, {
      type: 'ride_completed',
      title: 'Ride completed',
      body: `Paid ₹${ride.final_fare}. Thanks for riding!`,
      data: { rideId: String(ride.id) },
    });
  }
  if (driver) {
    realtime.toUser(driver.user_id, 'ride:payment_update', payload);
    realtime.toUser(driver.user_id, 'ride:completed', payload);
    notifyService.notify(driver.user_id, {
      type: 'ride_completed',
      title: 'Trip complete',
      body: `₹${ride.final_fare} collected. Earnings credited.`,
      data: { rideId: String(ride.id) },
    });
  }
}

const paymentService = {
  hasRazorpay,

  /**
   * Called by rideService right after DRIVER_COMPLETED → PAYMENT_PENDING.
   * Ensures a payment row exists for the ride's chosen method.
   */
  async ensureForRide(rideId, { method, idempotencyKey } = {}) {
    return db.withTransaction(async (tx) => {
      const ride = await rideRepo.findById(rideId, tx);
      if (!ride) throw ApiError.notFound('Ride not found');

      const paid = await paymentRepo.findPaidForRide(rideId, tx);
      if (paid) return { payment: paid, settled: true };

      if (idempotencyKey) {
        const existing = await paymentRepo.findByIdempotencyKey(idempotencyKey, tx);
        if (existing) return { payment: existing, settled: existing.status === 'paid' };
      }

      let existing = await paymentRepo.findLatestForRide(rideId, tx);
      const chosen = method || ride.payment_method || 'cash';
      if (existing && existing.status === 'pending' && existing.method === chosen) {
        return { payment: existing, method: chosen };
      }

      const amount = Number(ride.final_fare ?? 0);
      if (!(amount > 0)) throw ApiError.badRequest('Ride has no final fare yet', 'NO_FINAL_FARE');

      const gateway = GATEWAY_METHODS.has(chosen) ? 'razorpay' : null;
      const payment = await paymentRepo.create(
        { rideId, customerId: ride.customer_id, method: chosen, amount, gateway, idempotencyKey },
        tx,
      );
      await rideRepo.attachPayment(rideId, payment.id, chosen, tx);
      return { payment, method: chosen, amount };
    });
  },

  /**
   * UPI booking, step 1: quote the fare for a ride that doesn't exist yet and
   * open a Razorpay order against that amount — same createRazorpayOrder()
   * the post-ride flow uses, just before rideRepo.create() instead of after.
   * Never trusts a client-supplied fare, same principle as rideService.
   * createRide() itself: distance/duration/fare are always recomputed here,
   * not taken from the fare-selection screen the customer already saw.
   */
  async createPrebookOrder({ customerId, userId, pickup, drop, vehicleCategory, promoCode }) {
    const route = await geo.route(pickup, drop);
    let quote = await fareService.quote({
      category: vehicleCategory,
      distanceM: route.distanceM,
      durationS: route.durationS,
    });
    if (promoCode) {
      const p = await promoService.validate({ code: promoCode, userId, fare: quote.total });
      quote = await fareService.quote({
        category: vehicleCategory,
        distanceM: route.distanceM,
        durationS: route.durationS,
        promoDiscount: p.discount,
      });
    }
    if (!(quote.total > 0)) throw ApiError.badRequest('Invalid fare amount', 'BAD_FARE');

    const order = await createRazorpayOrder(Math.round(quote.total * 100), `prebook-${customerId}-${Date.now()}`);
    return {
      order: { id: order.id, amount: order.amount, currency: 'INR' },
      keyId: env.RAZORPAY_KEY_ID || null,
      stub: Boolean(order.stub),
      amount: quote.total,
    };
  },

  /**
   * Verify a UPI payment made BEFORE the ride existed. Pure signature check —
   * no DB access — so rideService.createRide() can call this BEFORE
   * rideRepo.create()/dispatchService.start() ever run. Throws on failure,
   * which the caller lets propagate so no ride is ever created for an
   * unpaid/failed/cancelled booking.
   */
  verifyPrebookSignature({ orderId, paymentId, signature }) {
    if (!isValidSignature(orderId, paymentId, signature)) {
      throw ApiError.badRequest('Payment signature verification failed', 'BAD_SIGNATURE');
    }
  },

  /**
   * UPI booking, step 2: called by rideService.createRide() right after the
   * ride row exists (a payment needs a real ride_id) — records the payment
   * already verified by verifyPrebookSignature as paid immediately. Does NOT
   * touch ride status (the ride is still REQUESTED/about to dispatch, not
   * anywhere near completion) — this only makes rideService.completeRide()
   * later see an already-paid payment via paymentRepo.findPaidForRide() and
   * settle straight through instead of asking the customer to pay again.
   */
  async recordPrebookPayment({ rideId, customerId, amount, orderId, paymentId }) {
    const payment = await paymentRepo.create({ rideId, customerId, method: 'upi', amount, gateway: 'razorpay' });
    await paymentRepo.setGatewayOrder(payment.id, orderId);
    await paymentRepo.markPaid(payment.id, { gatewayPaymentId: paymentId });
    await rideRepo.attachPayment(rideId, payment.id, 'upi');
    return payment;
  },

  /**
   * A ride reaching completion whose payment was already settled (a
   * pre-booked UPI ride) needs to close the loop exactly like settleCash()/
   * verifyClientPayment() do — advance PAYMENT_PENDING → COMPLETED and emit
   * the same events — instead of sitting stuck at PAYMENT_PENDING forever
   * because nothing else will ever call "confirm payment" for it.
   */
  async settleAlreadyPaid(rideId) {
    const paid = await paymentRepo.findPaidForRide(rideId);
    if (!paid) throw ApiError.conflict('No paid payment on file for this ride', 'NOT_PAID');
    const result = await db.withTransaction((tx) => settlePaidRide(tx, { rideId, paymentId: paid.id }));
    await emitSettled(result.ride);
    return result;
  },

  /** Customer taps "pay by UPI/card" → get a gateway order to open checkout. */
  async createGatewayOrder(rideId, customerProfileId, { idempotencyKey } = {}) {
    const { payment } = await this.ensureForRide(rideId, { method: 'upi', idempotencyKey });
    const ride = await rideRepo.findById(rideId);
    if (ride.customer_id !== customerProfileId) throw ApiError.forbidden();
    if (payment.status === 'paid') return { settled: true };

    const order = await createRazorpayOrder(Math.round(Number(payment.amount) * 100), payment.payment_ref);
    await paymentRepo.setGatewayOrder(payment.id, order.id);
    return {
      paymentId: payment.id,
      order: { id: order.id, amount: order.amount, currency: 'INR' },
      keyId: env.RAZORPAY_KEY_ID || null,
      stub: Boolean(order.stub),
    };
  },

  /** Driver confirms cash received. */
  async settleCash(rideId, driverProfileId) {
    const result = await db.withTransaction(async (tx) => {
      const ride = await rideRepo.findById(rideId, tx);
      if (!ride) throw ApiError.notFound('Ride not found');
      if (ride.driver_id !== driverProfileId) throw ApiError.forbidden();

      let payment = await paymentRepo.findLatestForRide(rideId, tx);
      if (!payment || payment.status === 'failed') {
        payment = await paymentRepo.create(
          { rideId, customerId: ride.customer_id, method: 'cash', amount: Number(ride.final_fare) },
          tx,
        );
      }
      if (payment.method !== 'cash') {
        throw ApiError.conflict('This ride is set to pay online', 'METHOD_MISMATCH');
      }
      const settled = await settlePaidRide(tx, { rideId, paymentId: payment.id });
      return settled;
    });
    await emitSettled(result.ride);
    return { ok: true, alreadySettled: result.alreadySettled };
  },

  /** Customer's app returns from Razorpay checkout with a signed payload. */
  async verifyClientPayment(rideId, customerProfileId, { orderId, paymentId, signature }) {
    if (!isValidSignature(orderId, paymentId, signature)) {
      throw ApiError.badRequest('Payment signature verification failed', 'BAD_SIGNATURE');
    }
    const result = await db.withTransaction(async (tx) => {
      const ride = await rideRepo.findById(rideId, tx);
      if (!ride) throw ApiError.notFound('Ride not found');
      if (ride.customer_id !== customerProfileId) throw ApiError.forbidden();
      const payment =
        (await paymentRepo.findLatestForRide(rideId, tx)) ??
        (await paymentRepo.create(
          { rideId, customerId: ride.customer_id, method: 'upi', amount: Number(ride.final_fare), gateway: 'razorpay' },
          tx,
        ));
      return settlePaidRide(tx, { rideId, paymentId: payment.id, gatewayPaymentId: paymentId });
    });
    await emitSettled(result.ride);
    return { ok: true, alreadySettled: result.alreadySettled };
  },

  /** Razorpay server-to-server webhook. */
  async handleWebhook(rawBody, signature) {
    if (env.RAZORPAY_WEBHOOK_SECRET) {
      const expected = hmacHex(env.RAZORPAY_WEBHOOK_SECRET, rawBody);
      if (!signature || signature !== expected) {
        throw ApiError.forbidden('Invalid webhook signature', 'BAD_WEBHOOK_SIG');
      }
    }
    let evt;
    try {
      evt = JSON.parse(rawBody);
    } catch {
      throw ApiError.badRequest('Malformed webhook body');
    }

    const eventId = evt.id || `${evt.event}:${evt?.payload?.payment?.entity?.id ?? crypto.randomUUID()}`;
    const entity = evt?.payload?.payment?.entity;
    const orderId = entity?.order_id;

    const first = await paymentRepo.recordEvent({
      paymentId: null,
      eventId,
      eventType: evt.event,
      payload: evt,
    });
    if (!first) return { duplicate: true };

    if (evt.event === 'payment.captured' && orderId) {
      const result = await db.withTransaction(async (tx) => {
        const payment = await tx.queryOne(
          `SELECT id, ride_id FROM rt_payments WHERE gateway_order_id = :orderId LIMIT 1`,
          { orderId },
        );
        if (!payment) return null;
        return settlePaidRide(tx, {
          rideId: payment.ride_id,
          paymentId: payment.id,
          gatewayPaymentId: entity.id,
        });
      });
      if (result) await emitSettled(result.ride);
    }
    await paymentRepo.markEventProcessed(eventId);
    return { ok: true };
  },

  async getForRide(rideId, requester) {
    const ride = await rideRepo.findById(rideId);
    if (!ride) throw ApiError.notFound('Ride not found');
    const owns =
      (requester.role === 'customer' && ride.customer_id === requester.profileId) ||
      (requester.role === 'driver' && ride.driver_id === requester.profileId);
    if (!owns) throw ApiError.forbidden();
    return paymentRepo.findLatestForRide(rideId);
  },
};

module.exports = paymentService;
