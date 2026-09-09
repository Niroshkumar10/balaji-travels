'use strict';

const rideService = require('../services/rideService');
const dispatchService = require('../services/dispatchService');
const ApiError = require('../utils/apiError');

const requester = (req) => ({
  role: req.auth.role,
  userId: req.auth.userId,
  profileId: req.auth.profileId,
});

module.exports = {
  async estimate(req, res) {
    const { pickup, drop, categories } = req.body;
    res.json({ success: true, ...(await rideService.estimate({ pickup, drop, categories })) });
  },

  async create(req, res) {
    const { pickup, drop, vehicleCategory, rideType, paymentMethod, promoCode } = req.body;
    const ride = await rideService.createRide({
      customer: { profileId: req.auth.profileId, userId: req.auth.userId },
      pickup,
      drop,
      vehicleCategory,
      rideType,
      paymentMethod,
      promoCode,
    });
    res.status(201).json({ success: true, ride });
  },

  async active(req, res) {
    res.json({ success: true, ride: await rideService.getActiveRide(requester(req)) });
  },

  async list(req, res) {
    const { limit, offset } = req.query;
    res.json({ success: true, rides: await rideService.listRides(requester(req), { limit, offset }) });
  },

  async get(req, res) {
    res.json({ success: true, ride: await rideService.getRide(Number(req.params.id), requester(req)) });
  },

  async history(req, res) {
    res.json({ success: true, history: await rideService.history(Number(req.params.id), requester(req)) });
  },

  async cancel(req, res) {
    const ride = await rideService.cancelRide(Number(req.params.id), requester(req), req.body.reason);
    res.json({ success: true, ride });
  },

  // ── driver intents (also available over sockets) ──
  async driverEnroute(req, res) {
    res.json({ success: true, ride: await rideService.driverEnroute(Number(req.params.id), req.auth.profileId) });
  },
  async driverArrived(req, res) {
    res.json({ success: true, ride: await rideService.driverArrived(Number(req.params.id), req.auth.profileId) });
  },
  async startRide(req, res) {
    res.json({
      success: true,
      ride: await rideService.startRide(Number(req.params.id), req.auth.profileId, req.body.otp),
    });
  },
  async completeRide(req, res) {
    res.json({
      success: true,
      ride: await rideService.completeRide(Number(req.params.id), req.auth.profileId, {
        waitingMinutes: req.body.waitingMinutes ?? 0,
      }),
    });
  },

  // driver responds to a dispatch offer via REST fallback (socket is primary)
  async respondOffer(req, res) {
    if (req.auth.role !== 'driver') throw ApiError.forbidden();
    const result = await dispatchService.handleOfferResponse(
      Number(req.params.id),
      req.auth.profileId,
      req.body.accept === true,
    );
    res.json({ success: result.ok, ...result });
  },
};
