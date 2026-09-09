'use strict';

/**
 * Small controllers grouped in one file to keep the tree flat:
 *   fare · places · payments · ratings · earnings · promos · notifications
 */

const ApiError = require('../utils/apiError');
const fareConfigRepo = require('../repositories/fareConfigRepo');
const placesService = require('../services/placesService');
const paymentService = require('../services/paymentService');
const ratingService = require('../services/ratingService');
const earningsService = require('../services/earningsService');
const promoService = require('../services/promoService');
const notificationRepo = require('../repositories/notificationRepo');

const requester = (req) => ({
  role: req.auth.role,
  userId: req.auth.userId,
  profileId: req.auth.profileId,
});

// ── fare ──────────────────────────────────────────────────────────────────
const fare = {
  async config(_req, res) {
    const rows = await fareConfigRepo.all();
    res.json({
      success: true,
      configs: rows.map((r) => ({
        category: r.vehicle_category,
        zone: r.zone,
        baseFare: Number(r.base_fare),
        includedKm: Number(r.included_km),
        perKm: Number(r.per_km),
        perMin: Number(r.per_min),
        minFare: Number(r.min_fare),
        waitingPerMin: Number(r.waiting_per_min),
        freeWaitingMin: r.free_waiting_min,
        cancellationFee: Number(r.cancellation_fee),
      })),
    });
  },
};

// ── places ────────────────────────────────────────────────────────────────
const places = {
  async autocomplete(req, res) {
    const { q, lat, lng } = req.query;
    res.json({
      success: true,
      predictions: await placesService.autocomplete(q, {
        lat: lat != null ? Number(lat) : undefined,
        lng: lng != null ? Number(lng) : undefined,
      }),
    });
  },
  async details(req, res) {
    const g = await placesService.geocode(req.query.placeId);
    if (!g) throw ApiError.notFound('Place not found or geocoding disabled');
    res.json({ success: true, place: g });
  },
  async reverse(req, res) {
    const { lat, lng } = req.query;
    res.json({ success: true, place: await placesService.reverseGeocode(Number(lat), Number(lng)) });
  },
  async listSaved(req, res) {
    res.json({ success: true, places: await placesService.listSaved(req.auth.profileId) });
  },
  async addSaved(req, res) {
    const id = await placesService.addSaved(req.auth.profileId, req.body);
    res.status(201).json({ success: true, id });
  },
  async removeSaved(req, res) {
    const ok = await placesService.removeSaved(req.auth.profileId, Number(req.params.id));
    if (!ok) throw ApiError.notFound('Saved place not found');
    res.json({ success: true });
  },
};

// ── payments ──────────────────────────────────────────────────────────────
const payments = {
  async createOrder(req, res) {
    const out = await paymentService.createGatewayOrder(Number(req.params.id), req.auth.profileId, {
      idempotencyKey: req.headers['idempotency-key'] || req.body.idempotencyKey,
    });
    res.json({ success: true, ...out });
  },
  async confirm(req, res) {
    // customer returns from Razorpay checkout
    const out = await paymentService.verifyClientPayment(Number(req.params.id), req.auth.profileId, {
      orderId: req.body.orderId,
      paymentId: req.body.paymentId,
      signature: req.body.signature,
    });
    res.json({ success: true, ...out });
  },
  async settleCash(req, res) {
    if (req.auth.role !== 'driver') throw ApiError.forbidden();
    const out = await paymentService.settleCash(Number(req.params.id), req.auth.profileId);
    res.json({ success: true, ...out });
  },
  async getForRide(req, res) {
    res.json({
      success: true,
      payment: await paymentService.getForRide(Number(req.params.id), requester(req)),
    });
  },
  async webhook(req, res) {
    const out = await paymentService.handleWebhook(
      req.rawBody ?? JSON.stringify(req.body ?? {}),
      req.headers['x-razorpay-signature'],
    );
    res.json({ received: true, ...out });
  },
};

// ── ratings ───────────────────────────────────────────────────────────────
const ratings = {
  async rate(req, res) {
    await ratingService.rate(Number(req.params.id), {
      byRole: req.auth.role,
      raterUserId: req.auth.userId,
      raterProfileId: req.auth.profileId,
      stars: req.body.stars,
      comment: req.body.comment,
      tags: req.body.tags,
    });
    res.status(201).json({ success: true });
  },
  async forRide(req, res) {
    res.json({ success: true, ratings: await ratingService.forRide(Number(req.params.id)) });
  },
};

// ── earnings (driver) ─────────────────────────────────────────────────────
const earnings = {
  async summary(req, res) {
    res.json({
      success: true,
      summary: await earningsService.summary(req.auth.profileId, req.query.period ?? 'day'),
    });
  },
  async ledger(req, res) {
    res.json({
      success: true,
      ledger: await earningsService.ledger(req.auth.profileId, {
        limit: req.query.limit,
        offset: req.query.offset,
      }),
    });
  },
  async payout(req, res) {
    res.status(201).json({
      success: true,
      payout: await earningsService.requestPayout(req.auth.profileId, req.body.amount),
    });
  },
  async payouts(req, res) {
    res.json({ success: true, payouts: await earningsService.listPayouts(req.auth.profileId) });
  },
};

// ── promos ────────────────────────────────────────────────────────────────
const promos = {
  async apply(req, res) {
    const out = await promoService.validate({
      code: req.body.code,
      userId: req.auth.userId,
      fare: Number(req.body.fare),
    });
    res.json({ success: true, ...out });
  },
  async list(_req, res) {
    const rows = await promoService.list();
    res.json({
      success: true,
      promos: rows
        .filter((p) => p.is_active)
        .map((p) => ({
          code: p.code,
          description: p.description,
          type: p.type,
          value: Number(p.value),
          maxDiscount: p.max_discount != null ? Number(p.max_discount) : null,
          minFare: Number(p.min_fare),
        })),
    });
  },
};

// ── notifications ─────────────────────────────────────────────────────────
const notifications = {
  async list(req, res) {
    const [items, unread] = await Promise.all([
      notificationRepo.list(req.auth.userId, { limit: req.query.limit, offset: req.query.offset }),
      notificationRepo.unreadCount(req.auth.userId),
    ]);
    res.json({ success: true, unread, notifications: items });
  },
  async markRead(req, res) {
    const ok = await notificationRepo.markRead(req.auth.userId, Number(req.params.id));
    res.json({ success: ok });
  },
  async markAllRead(req, res) {
    await notificationRepo.markAllRead(req.auth.userId);
    res.json({ success: true });
  },
};

module.exports = { fare, places, payments, ratings, earnings, promos, notifications };
