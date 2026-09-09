'use strict';

/**
 * The ride lifecycle — the ONLY place legal transitions are defined.
 *
 * `resolve(currentStatus, event)` returns { to, tsField } or throws
 * InvalidTransitionError. rideRepo.transition() then applies the ride UPDATE
 * and appends rt_ride_status_history in ONE transaction, so status and history
 * can never diverge, and an impossible move (e.g. COMPLETED → DRIVER_ARRIVING)
 * is rejected before any write.
 *
 * Clients send an INTENT EVENT (start_ride, complete, cancel, ...), never a
 * status string — the server maps event → transition.
 */

const ApiError = require('../utils/apiError');

const STATUSES = [
  'REQUESTED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVING',
  'DRIVER_ARRIVED', 'RIDE_STARTED', 'RIDE_IN_PROGRESS', 'DRIVER_COMPLETED',
  'PAYMENT_PENDING', 'COMPLETED',
  'CUSTOMER_CANCELLED', 'DRIVER_CANCELLED', 'SYSTEM_CANCELLED',
  'NO_DRIVERS_FOUND', 'PAYMENT_FAILED',
];

const TERMINAL = new Set([
  'COMPLETED', 'CUSTOMER_CANCELLED', 'DRIVER_CANCELLED', 'SYSTEM_CANCELLED', 'NO_DRIVERS_FOUND',
]);

// "Active" = a driver is (or was) attached and the ride is not finished.
// Mirrors the rt_rides.active_driver_id generated column exactly.
const DRIVER_ACTIVE = new Set([
  'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED',
  'RIDE_STARTED', 'RIDE_IN_PROGRESS', 'DRIVER_COMPLETED', 'PAYMENT_PENDING',
]);

const CUSTOMER_CANCELLABLE = new Set([
  'REQUESTED', 'SEARCHING_DRIVER', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED',
]);
const DRIVER_CANCELLABLE = new Set(['DRIVER_ASSIGNED', 'DRIVER_ARRIVING', 'DRIVER_ARRIVED']);

/**
 * event → { from:Set, to, actor, tsField?, terminal? }
 */
const TRANSITIONS = {
  search:            { from: new Set(['REQUESTED']),                       to: 'SEARCHING_DRIVER', actor: 'system' },
  assign:            { from: new Set(['SEARCHING_DRIVER']),                to: 'DRIVER_ASSIGNED',  actor: 'system', tsField: 'assigned_at' },
  no_drivers:        { from: new Set(['SEARCHING_DRIVER', 'REQUESTED']),   to: 'NO_DRIVERS_FOUND', actor: 'system' },
  driver_enroute:    { from: new Set(['DRIVER_ASSIGNED']),                 to: 'DRIVER_ARRIVING',  actor: 'driver' },
  driver_arrived:    { from: new Set(['DRIVER_ASSIGNED', 'DRIVER_ARRIVING']), to: 'DRIVER_ARRIVED', actor: 'driver', tsField: 'driver_arrived_at' },
  start_ride:        { from: new Set(['DRIVER_ARRIVED']),                  to: 'RIDE_STARTED',     actor: 'driver', tsField: 'started_at', needsOtp: true },
  trip_progress:     { from: new Set(['RIDE_STARTED']),                    to: 'RIDE_IN_PROGRESS', actor: 'system' },
  complete:          { from: new Set(['RIDE_STARTED', 'RIDE_IN_PROGRESS']), to: 'DRIVER_COMPLETED', actor: 'driver' },
  to_payment:        { from: new Set(['DRIVER_COMPLETED']),               to: 'PAYMENT_PENDING',  actor: 'system' },
  payment_ok:        { from: new Set(['PAYMENT_PENDING']),                to: 'COMPLETED',        actor: 'system', tsField: 'completed_at' },
  payment_failed:    { from: new Set(['PAYMENT_PENDING']),                to: 'PAYMENT_FAILED',   actor: 'system' },
  payment_retry:     { from: new Set(['PAYMENT_FAILED']),                 to: 'PAYMENT_PENDING',  actor: 'system' },
  cancel_customer:   { from: CUSTOMER_CANCELLABLE,                        to: 'CUSTOMER_CANCELLED', actor: 'customer', tsField: 'cancelled_at' },
  cancel_driver:     { from: DRIVER_CANCELLABLE,                          to: 'DRIVER_CANCELLED',   actor: 'driver',   tsField: 'cancelled_at' },
  cancel_system:     { from: new Set(STATUSES.filter((s) => !TERMINAL.has(s))), to: 'SYSTEM_CANCELLED', actor: 'system', tsField: 'cancelled_at' },
};

class InvalidTransitionError extends ApiError {
  constructor(current, event) {
    super(409, 'INVALID_TRANSITION', `Cannot '${event}' from status '${current}'`);
    this.current = current;
    this.event = event;
  }
}

/**
 * @param {string} current  current rt_rides.status
 * @param {string} event    one of Object.keys(TRANSITIONS)
 * @returns {{ event:string, to:string, tsField:(string|null), actor:string, needsOtp:boolean }}
 */
function resolve(current, event) {
  const t = TRANSITIONS[event];
  if (!t) throw new ApiError(400, 'UNKNOWN_EVENT', `Unknown ride event '${event}'`);
  if (!t.from.has(current)) throw new InvalidTransitionError(current, event);
  return {
    event,
    to: t.to,
    tsField: t.tsField ?? null,
    actor: t.actor,
    needsOtp: Boolean(t.needsOtp),
  };
}

/** Guard: the acting role is allowed to drive this event at all. */
function assertActor(event, actorRole) {
  const t = TRANSITIONS[event];
  if (!t) throw new ApiError(400, 'UNKNOWN_EVENT', `Unknown ride event '${event}'`);
  if (t.actor !== actorRole && actorRole !== 'system') {
    throw ApiError.forbidden(`Role '${actorRole}' cannot perform '${event}'`, 'EVENT_ROLE_FORBIDDEN');
  }
}

module.exports = {
  STATUSES,
  TERMINAL,
  DRIVER_ACTIVE,
  TRANSITIONS,
  resolve,
  assertActor,
  InvalidTransitionError,
  isTerminal: (s) => TERMINAL.has(s),
};
