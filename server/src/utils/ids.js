'use strict';

/**
 * Business reference builders.
 *
 * Every human-facing reference is derived from the row's own AUTO_INCREMENT id
 * — assigned atomically by the database, so two concurrent inserts can never
 * collide. This is the deliberate replacement for `Date.now()`-based ids,
 * which the Microlab load tests proved collide under load (LT-002/LT-011).
 */

const pad = (n, width) => String(n).padStart(width, '0');

const rideRef = (id) => `RIDE-${pad(id, 8)}`;
const paymentRef = (id) => `PAY-${pad(id, 8)}`;
const payoutRef = (id) => `PO-${pad(id, 8)}`;

module.exports = { rideRef, paymentRef, payoutRef, pad };
