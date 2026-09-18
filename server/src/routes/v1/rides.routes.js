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

// UPI booking, step 1 — quote + open a Razorpay order before any ride exists.
// See rideService.createRide()'s `payment` handling for step 2.
router.post(
  '/prebook-order',
  requireRole('customer'),
  validate({
    body: z.object({
      pickup: place,
      drop: place,
      vehicleCategory,
      promoCode: z.string().trim().min(3).max(40).optional(),
    }),
  }),
  asyncHandler(ctrl.prebookOrder),
);

// Rental fare step — all 10 package tiers (1hr/10km .. 10hr/100km) quoted
// for one vehicle category. Registered before GET /:id so "rental-packages"
// is never swallowed as an :id.
router.get(
  '/rental-packages',
  requireRole('customer'),
  validate({ query: z.object({ vehicleCategory }) }),
  asyncHandler(ctrl.rentalPackages),
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
      rideType: z.enum(['local', 'outstation', 'round_trip', 'rental']).optional(),
      paymentMethod: paymentMethod.optional(),
      promoCode: z.string().trim().min(3).max(40).optional(),
      // Required when paymentMethod is 'upi' — the Razorpay payment already
      // made against the order from POST /rides/prebook-order.
      payment: z
        .object({
          orderId: z.string().min(1),
          paymentId: z.string().min(1),
          signature: z.string().optional(),
        })
        .optional(),
      // Required when rideType is 'rental' — one of rentalService.PACKAGE_HOURS.
      rentalPackageHours: z.coerce.number().int().min(1).max(10).optional(),
      // Optional on any ride type — a future pickup time. See
      // jobs/scheduledDispatch.js: dispatch is held back until then instead
      // of starting immediately.
      scheduledAt: z.coerce.date().optional(),
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
