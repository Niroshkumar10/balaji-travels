'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const hmacAdmin = require('../../middleware/hmacAdmin');
const asyncHandler = require('../../utils/asyncHandler');
const { vehicleCategory } = require('../../utils/validators');
const ops = require('../../controllers/opsController');

const router = Router();
router.use(hmacAdmin);

router.get('/drivers', asyncHandler(ops.listDrivers));
router.post(
  '/drivers/:driverId/kyc',
  validate({ body: z.object({ status: z.enum(['approved', 'rejected', 'suspended', 'pending']), reason: z.string().max(255).optional() }) }),
  asyncHandler(ops.setKyc),
);

router.get('/rides', asyncHandler(ops.listRides));

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
