-- Rental/outstation bookings wait here for an ops admin to hand-pick a
-- driver instead of auto-dispatch's distance-sorted cascade (see
-- rideStateMachine.js's await_admin / admin_offer / admin_offer_failed
-- events and services/adminAssignmentService.js).
ALTER TABLE rt_rides
  MODIFY status ENUM(
    'REQUESTED','SEARCHING_DRIVER','PENDING_ADMIN_ASSIGNMENT','DRIVER_ASSIGNED','DRIVER_ARRIVING',
    'DRIVER_ARRIVED','RIDE_STARTED','RIDE_IN_PROGRESS','DRIVER_COMPLETED',
    'PAYMENT_PENDING','COMPLETED',
    'CUSTOMER_CANCELLED','DRIVER_CANCELLED','SYSTEM_CANCELLED',
    'NO_DRIVERS_FOUND','PAYMENT_FAILED'
  ) NOT NULL DEFAULT 'REQUESTED';
