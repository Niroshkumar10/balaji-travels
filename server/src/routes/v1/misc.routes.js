'use strict';

/**
 * Route groups for the smaller domains: fare · places · payments · ratings ·
 * earnings · promos · notifications. Mounted individually in routes/v1/index.js.
 */

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const requireRole = require('../../middleware/role');
const asyncHandler = require('../../utils/asyncHandler');
const { lat, lng } = require('../../utils/validators');
const c = require('../../controllers/miscControllers');

// ── /fare ──
const fare = Router();
fare.get('/config', asyncHandler(c.fare.config));

// ── /places ──
const places = Router();
places.use(authenticate);
places.get(
  '/autocomplete',
  validate({ query: z.object({ q: z.string().trim().min(1).max(120), lat: lat.optional(), lng: lng.optional() }) }),
  asyncHandler(c.places.autocomplete),
);
places.get('/details', validate({ query: z.object({ placeId: z.string().min(1) }) }), asyncHandler(c.places.details));
places.get('/reverse', validate({ query: z.object({ lat, lng }) }), asyncHandler(c.places.reverse));
places.get('/saved', requireRole('customer'), asyncHandler(c.places.listSaved));
places.post(
  '/saved',
  requireRole('customer'),
  validate({ body: z.object({ label: z.string().trim().min(1).max(80), lat, lng, addr: z.string().trim().max(400).optional() }) }),
  asyncHandler(c.places.addSaved),
);
places.delete('/saved/:id', requireRole('customer'), asyncHandler(c.places.removeSaved));

// ── /payments ──
const payments = Router();
payments.post('/webhook', asyncHandler(c.payments.webhook)); // no auth — signature verified in service
payments.use(authenticate);
payments.post('/rides/:id/order', requireRole('customer'), asyncHandler(c.payments.createOrder));
payments.post(
  '/rides/:id/confirm',
  requireRole('customer'),
  validate({ body: z.object({ orderId: z.string().optional(), paymentId: z.string().optional(), signature: z.string().optional() }) }),
  asyncHandler(c.payments.confirm),
);
payments.post('/rides/:id/cash', requireRole('driver'), asyncHandler(c.payments.settleCash));
payments.get('/rides/:id', asyncHandler(c.payments.getForRide));

// ── /ratings (nested under a ride) ──
const ratings = Router();
ratings.use(authenticate);
ratings.post(
  '/rides/:id',
  validate({
    body: z.object({
      stars: z.coerce.number().int().min(1).max(5),
      comment: z.string().trim().max(500).optional(),
      tags: z.array(z.string().max(40)).max(8).optional(),
    }),
  }),
  asyncHandler(c.ratings.rate),
);
ratings.get('/rides/:id', asyncHandler(c.ratings.forRide));

// ── /earnings (driver) ──
const earnings = Router();
earnings.use(authenticate, requireRole('driver'));
earnings.get('/summary', validate({ query: z.object({ period: z.enum(['day', 'week', 'month', 'all']).optional() }) }), asyncHandler(c.earnings.summary));
earnings.get('/ledger', asyncHandler(c.earnings.ledger));
earnings.get('/payouts', asyncHandler(c.earnings.payouts));
earnings.post('/payout', validate({ body: z.object({ amount: z.coerce.number().positive() }) }), asyncHandler(c.earnings.payout));

// ── /promos ──
const promos = Router();
promos.use(authenticate);
promos.get('/', asyncHandler(c.promos.list));
promos.post(
  '/apply',
  requireRole('customer'),
  validate({ body: z.object({ code: z.string().trim().min(3).max(40), fare: z.coerce.number().positive() }) }),
  asyncHandler(c.promos.apply),
);

// ── /notifications ──
const notifications = Router();
notifications.use(authenticate);
notifications.get('/', asyncHandler(c.notifications.list));
notifications.post('/read-all', asyncHandler(c.notifications.markAllRead));
notifications.post('/:id/read', asyncHandler(c.notifications.markRead));

module.exports = { fare, places, payments, ratings, earnings, promos, notifications };
