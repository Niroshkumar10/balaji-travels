'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const hmacAdmin = require('../../middleware/hmacAdmin');
const asyncHandler = require('../../utils/asyncHandler');
const { vehicleCategory, paymentMethod, mobile, lat, lng, rideType, serviceTypes } = require('../../utils/validators');
const ops = require('../../controllers/opsController');

const router = Router();
router.use(hmacAdmin);

router.get('/drivers', asyncHandler(ops.listDrivers));

const bookingPlace = z.object({ lat, lng, addr: z.string().trim().max(400).optional() });
const createBookingBody = z
  .object({
    adminId: z.coerce.number().int().positive(),
    customerId: z.coerce.number().int().positive().optional(),
    customerMobile: mobile.optional(),
    pickup: bookingPlace,
    drop: bookingPlace,
    vehicleCategory,
    rideType: rideType.optional(),
    paymentMethod: paymentMethod.optional(),
    promoCode: z.string().trim().min(3).max(40).optional(),
  })
  .strict()
  .refine((b) => b.customerId || b.customerMobile, {
    message: 'customerId or customerMobile is required',
  });

// Admin/call-in booking — same rideService.createRide() + dispatchService.start()
// path a normal customer booking uses (see opsController.createBooking).
router.post('/bookings', validate({ body: createBookingBody }), asyncHandler(ops.createBooking));
router.post(
  '/drivers/:driverId/kyc',
  validate({ body: z.object({ status: z.enum(['approved', 'rejected', 'suspended', 'pending']), reason: z.string().max(255).optional() }) }),
  asyncHandler(ops.setKyc),
);
router.post(
  '/drivers/:driverId/services',
  validate({ body: z.object({ serviceTypes, adminId: z.coerce.number().int().positive().optional() }) }),
  asyncHandler(ops.setDriverServices),
);

router.get('/rides', asyncHandler(ops.listRides));
router.get('/rides/:rideId/candidates', asyncHandler(ops.rideCandidates));
router.post(
  '/rides/:rideId/assign',
  validate({
    body: z.object({
      driverId: z.coerce.number().int().positive(),
      adminId: z.coerce.number().int().positive(),
    }),
  }),
  asyncHandler(ops.assignRideDriver),
);

router.post(
  '/fare-config',
  validate({
    body: z.object({
      category: vehicleCategory,
      zone: z.string().max(60).optional(),
      baseFare: z.coerce.number().nonnegative(),
      includedKm: z.coerce.number().nonnegative().optional(),
      perKm: z.coerce.number().nonnegative(),
      perMin: z.coerce.number().nonnegative().optional(),
      minFare: z.coerce.number().nonnegative(),
      waitingPerMin: z.coerce.number().nonnegative().optional(),
      freeWaitingMin: z.coerce.number().int().nonnegative().optional(),
      surgeMultiplier: z.coerce.number().positive().optional(),
      nightMultiplier: z.coerce.number().positive().optional(),
      nightStart: z.string().regex(/^\d{2}:\d{2}(:\d{2})?$/).optional(),
      nightEnd: z.string().regex(/^\d{2}:\d{2}(:\d{2})?$/).optional(),
      cancellationFee: z.coerce.number().nonnegative().optional(),
    }),
  }),
  asyncHandler(ops.upsertFare),
);

module.exports = router;
