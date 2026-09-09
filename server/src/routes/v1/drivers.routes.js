'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const requireRole = require('../../middleware/role');
const asyncHandler = require('../../utils/asyncHandler');
const { vehicleCategory, lat, lng } = require('../../utils/validators');
const profile = require('../../controllers/profileController');
const presence = require('../../controllers/presenceController');

const router = Router();

const patchBody = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    email: z.string().trim().email().max(160).optional(),
    licenseNo: z.string().trim().min(4).max(60).optional(),
  })
  .strict();

const vehicleBody = z
  .object({
    category: vehicleCategory,
    make: z.string().trim().max(60).optional(),
    model: z.string().trim().max(60).optional(),
    plateNo: z
      .string()
      .trim()
      .toUpperCase()
      .regex(/^[A-Z0-9- ]{4,20}$/, 'Invalid plate number'),
    color: z.string().trim().max(30).optional(),
    year: z.coerce.number().int().min(1980).max(new Date().getFullYear() + 1).optional(),
  })
  .strict();

const geoBody = z.object({ lat, lng, bearing: z.coerce.number().optional(), speedKmph: z.coerce.number().optional(), battery: z.coerce.number().int().min(0).max(100).optional() });

router.use(authenticate, requireRole('driver'));

router.get('/me', asyncHandler(profile.getDriverMe));
router.patch('/me', validate({ body: patchBody }), asyncHandler(profile.patchDriverMe));
router.get('/me/vehicles', asyncHandler(profile.listVehicles));
router.post('/me/vehicle', validate({ body: vehicleBody }), asyncHandler(profile.addVehicle));

// presence (socket is the primary path; these REST endpoints are a fallback)
router.post('/me/online', validate({ body: z.object({ lat, lng }) }), asyncHandler(presence.goOnline));
router.post('/me/offline', asyncHandler(presence.goOffline));
router.post('/me/heartbeat', validate({ body: geoBody }), asyncHandler(presence.heartbeat));

module.exports = router;
