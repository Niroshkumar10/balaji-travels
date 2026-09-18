'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const requireRole = require('../../middleware/role');
const asyncHandler = require('../../utils/asyncHandler');
const { vehicleCategory, lat, lng, serviceTypes } = require('../../utils/validators');
const profile = require('../../controllers/profileController');
const presence = require('../../controllers/presenceController');
const { uploadDoc } = require('../../middleware/upload');

const router = Router();

const patchBody = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    email: z.string().trim().email().max(160).optional(),
    licenseNo: z.string().trim().min(4).max(60).optional(),
    // Which bookings this driver receives — local / rental / outstation,
    // any combination, at least one (see server/src/utils/serviceType.js).
    serviceTypes: serviceTypes.optional(),
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

// Dates arrive as multipart text fields (e.g. "2027-06-30"); coerced straight
// to a Date so mysql2 gets a real DATE value, same as the JSON routes do.
const isoDate = z.coerce.date();

const driverDocBody = z
  .object({
    docType: z.enum(['license', 'id_proof', 'photo']),
    number: z.string().trim().min(1).max(60).optional(),
    expiry: isoDate.optional(),
    // Matches rt_drivers.id_proof_type's actual enum exactly (checked against
    // the live schema — do not add/rename values here without a migration).
    idProofType: z.enum(['aadhaar', 'pan', 'voter_id', 'passport', 'other']).optional(),
  })
  .strict();

const vehicleDocBody = z
  .object({
    docType: z.enum(['rc', 'insurance', 'permit', 'fitness', 'puc']),
    number: z.string().trim().min(1).max(60).optional(),
    expiry: isoDate.optional(),
  })
  .strict();

router.use(authenticate, requireRole('driver'));

router.get('/me', asyncHandler(profile.getDriverMe));
router.patch('/me', validate({ body: patchBody }), asyncHandler(profile.patchDriverMe));
router.get('/me/vehicles', asyncHandler(profile.listVehicles));
router.post('/me/vehicle', validate({ body: vehicleBody }), asyncHandler(profile.addVehicle));

// KYC/document uploads — multer runs first so req.body's text fields exist
// for `validate` to check; the file itself is req.file (see upload.js).
router.post(
  '/me/documents',
  uploadDoc.single('file'),
  validate({ body: driverDocBody }),
  asyncHandler(profile.uploadDriverDocument),
);
router.post(
  '/me/vehicle/documents',
  uploadDoc.single('file'),
  validate({ body: vehicleDocBody }),
  asyncHandler(profile.uploadVehicleDocument),
);

// presence (socket is the primary path; these REST endpoints are a fallback)
router.post('/me/online', validate({ body: z.object({ lat, lng }) }), asyncHandler(presence.goOnline));
router.post('/me/offline', asyncHandler(presence.goOffline));
router.post('/me/heartbeat', validate({ body: geoBody }), asyncHandler(presence.heartbeat));

module.exports = router;
