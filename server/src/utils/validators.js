'use strict';

/** Shared Zod field schemas — one definition per concept, reused across routes. */
const { z } = require('zod');

// Indian mobile: 10 digits, starts 6-9. Strip a leading +91 / 91 / 0 first.
const mobile = z
  .string()
  .trim()
  .transform((s) => s.replace(/^(\+?91|0)/, ''))
  .pipe(z.string().regex(/^[6-9]\d{9}$/, 'Invalid mobile number'));

const loginRole = z.enum(['customer', 'driver']);

const otpCode = z
  .string()
  .trim()
  .regex(/^\d{4,8}$/, 'Invalid code');

const lat = z.coerce.number().min(-90).max(90);
const lng = z.coerce.number().min(-180).max(180);

const latLng = z.object({ lat, lng });

const paymentMethod = z.enum(['cash', 'upi', 'card', 'wallet']);
const vehicleCategory = z.enum(['bike', 'auto', 'hatchback', 'sedan', 'suv']);
const rideType = z.enum(['local', 'outstation', 'round_trip', 'rental']);
// At least one — a driver with no services would never be offered a ride.
const serviceTypes = z.array(z.enum(['local', 'rental', 'outstation'])).min(1).max(3);

const idParam = z.object({ id: z.coerce.number().int().positive() });

module.exports = {
  mobile,
  loginRole,
  otpCode,
  lat,
  lng,
  latLng,
  paymentMethod,
  vehicleCategory,
  rideType,
  serviceTypes,
  idParam,
};
