'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const requireRole = require('../../middleware/role');
const asyncHandler = require('../../utils/asyncHandler');
const { lat, lng, vehicleCategory, paymentMethod } = require('../../utils/validators');
const ctrl = require('../../controllers/rideController');

const router = Router();
router.use(authenticate);

const place = z.object({
  lat,
  lng,
  addr: z.string().trim().max(400).optional(),
});

// ── estimate (no ride created) — either role may price a trip ──
router.post(
  '/estimate',
  validate({
    body: z.object({
      pickup: place,
      drop: place,
      categories: z.array(vehicleCategory).max(5).optional(),
    }),
  }),
  asyncHandler(ctrl.estimate),
);

// ── customer: create / list / get / cancel ──
router.post(
  '/',
  requireRole('customer'),
  validate({
    body: z.object({
      pickup: place,
      drop: place,
      vehicleCategory,
      rideType: z.enum(['local', 'outstation', 'round_trip']).optional(),
      paymentMethod: paymentMethod.optional(),
      promoCode: z.string().trim().min(3).max(40).optional(),
    }),
  }),
  asyncHandler(ctrl.create),
);

router.get('/active', asyncHandler(ctrl.active));
router.get(
  '/',
  validate({
    query: z.object({
      limit: z.coerce.number().int().min(1).max(50).optional(),
      offset: z.coerce.number().int().min(0).optional(),
    }),
  }),
  asyncHandler(ctrl.list),
);
router.get('/:id', asyncHandler(ctrl.get));
router.get('/:id/history', asyncHandler(ctrl.history));

router.post(
  '/:id/cancel',
  validate({ body: z.object({ reason: z.string().trim().max(255).optional() }) }),
  asyncHandler(ctrl.cancel),
);

// ── driver: dispatch response + trip milestones (socket is primary path) ──
router.post(
  '/:id/offer-response',
  requireRole('driver'),
  validate({ body: z.object({ accept: z.boolean() }) }),
  asyncHandler(ctrl.respondOffer),
);
router.post('/:id/enroute', requireRole('driver'), asyncHandler(ctrl.driverEnroute));
router.post('/:id/arrived', requireRole('driver'), asyncHandler(ctrl.driverArrived));
router.post(
  '/:id/start',
  requireRole('driver'),
  validate({ body: z.object({ otp: z.string().trim().regex(/^\d{4}$/) }) }),
  asyncHandler(ctrl.startRide),
);
router.post(
  '/:id/complete',
  requireRole('driver'),
  validate({ body: z.object({ waitingMinutes: z.coerce.number().int().min(0).max(240).optional() }) }),
  asyncHandler(ctrl.completeRide),
);

module.exports = router;
