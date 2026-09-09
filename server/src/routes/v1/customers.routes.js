'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const requireRole = require('../../middleware/role');
const asyncHandler = require('../../utils/asyncHandler');
const { lat, lng, paymentMethod } = require('../../utils/validators');
const ctrl = require('../../controllers/profileController');

const router = Router();

const patchBody = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    email: z.string().trim().email().max(160).optional(),
    defaultPaymentMethod: paymentMethod.optional(),
    homeLabel: z.string().trim().max(120).optional(),
    homeLat: lat.optional(),
    homeLng: lng.optional(),
    homeAddr: z.string().trim().max(400).optional(),
    workLabel: z.string().trim().max(120).optional(),
    workLat: lat.optional(),
    workLng: lng.optional(),
    workAddr: z.string().trim().max(400).optional(),
  })
  .strict();

router.use(authenticate, requireRole('customer'));

router.get('/me', asyncHandler(ctrl.getCustomerMe));
router.patch('/me', validate({ body: patchBody }), asyncHandler(ctrl.patchCustomerMe));

module.exports = router;
