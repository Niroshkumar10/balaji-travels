'use strict';

/**
 * Operational endpoints — no admin web is in scope, so these exist only for
 * the handful of actions the ride flow can't run without: approving driver
 * KYC and adjusting fare config. Guarded by the HMAC-SHA256 shared secret
 * (middleware/hmacAdmin), never an end-user JWT.
 */

const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const driverRepo = require('../repositories/driverRepo');
const fareConfigRepo = require('../repositories/fareConfigRepo');
const userRepo = require('../repositories/userRepo');
const customerRepo = require('../repositories/customerRepo');
const rideService = require('../services/rideService');

module.exports = {
  async listDrivers(req, res) {
    const status = req.query.kyc;
    const rows = await db.query(
      `SELECT d.id, d.kyc_status, d.rating_avg, d.rating_count, d.is_online, d.availability,
              u.mobile, u.name, u.email,
              (SELECT COUNT(*) FROM rt_vehicles v WHERE v.driver_id = d.id AND v.deleted_at IS NULL) AS vehicle_count
         FROM rt_drivers d JOIN rt_users u ON u.id = d.user_id
        ${status ? 'WHERE d.kyc_status = :status' : ''}
        ORDER BY d.id DESC LIMIT 200`,
      status ? { status } : {},
    );
    res.json({ success: true, drivers: rows });
  },

  async setKyc(req, res) {
    const driverId = Number(req.params.driverId);
    const { status, reason } = req.body;
    if (!['approved', 'rejected', 'suspended', 'pending'].includes(status)) {
      throw ApiError.badRequest('Invalid kyc status');
    }
    const driver = await driverRepo.findById(driverId);
    if (!driver) throw ApiError.notFound('Driver not found');
    await driverRepo.setKyc(driverId, { status, reviewerId: null, reason });
    await db.query(
      `INSERT INTO rt_admin_audit (admin_id, action, entity, entity_id, before_val, after_val)
       VALUES (NULL, 'kyc_update', 'driver', :id, :before, :after)`,
      {
        id: String(driverId),
        before: JSON.stringify({ kyc_status: driver.kyc_status }),
        after: JSON.stringify({ kyc_status: status, reason: reason ?? null }),
      },
    );
    res.json({ success: true, driverId, kycStatus: status });
  },

  async upsertFare(req, res) {
    const b = req.body;
    await fareConfigRepo.upsert({
      vehicleCategory: b.category,
      zone: b.zone ?? 'default',
      baseFare: b.baseFare,
      includedKm: b.includedKm ?? 0,
      perKm: b.perKm,
      perMin: b.perMin ?? 0,
      minFare: b.minFare,
      waitingPerMin: b.waitingPerMin ?? 0,
      freeWaitingMin: b.freeWaitingMin ?? 3,
      surgeMultiplier: b.surgeMultiplier ?? 1,
      nightMultiplier: b.nightMultiplier ?? 1,
      nightStart: b.nightStart ?? null,
      nightEnd: b.nightEnd ?? null,
      cancellationFee: b.cancellationFee ?? 0,
    });
    res.json({ success: true });
  },

  /**
   * Admin/phone (call-in) booking — creates a ride through the EXACT same
   * rideService.createRide() → dispatchService.start() path a normal
   * customer booking uses. No offer/OTP/dispatch logic is duplicated here;
   * this only resolves which customer the ride is for and tags the source.
   */
  async createBooking(req, res) {
    const b = req.body;

    let customer = null;
    if (b.customerId) {
      customer = await customerRepo.findById(Number(b.customerId));
    } else if (b.customerMobile) {
      const user = await userRepo.findByMobileAndRole(b.customerMobile, 'customer');
      if (user) customer = await customerRepo.findByUserId(user.id);
    }
    if (!customer) throw ApiError.notFound('Customer not found — check customerId/customerMobile', 'CUSTOMER_NOT_FOUND');

    const ride = await rideService.createRide({
      customer: { profileId: customer.id, userId: customer.user_id },
      pickup: b.pickup,
      drop: b.drop,
      vehicleCategory: b.vehicleCategory,
      rideType: b.rideType,
      paymentMethod: b.paymentMethod,
      promoCode: b.promoCode,
      bookingSource: 'admin_call',
      createdByAdminId: b.adminId,
    });

    await db.query(
      `INSERT INTO rt_admin_audit (admin_id, action, entity, entity_id, before_val, after_val)
       VALUES (:adminId, 'booking_create', 'ride', :rideId, NULL, :after)`,
      {
        adminId: b.adminId,
        rideId: String(ride.id),
        after: JSON.stringify({ customerId: customer.id, vehicleCategory: b.vehicleCategory, status: ride.status }),
      },
    );

    res.status(201).json({ success: true, ride });
  },

  async listRides(req, res) {
    const rows = await db.query(
      `SELECT id, ride_ref, status, vehicle_category, customer_id, driver_id,
              est_fare, final_fare, requested_at, completed_at
         FROM rt_rides
        ${req.query.status ? 'WHERE status = :status' : ''}
        ORDER BY id DESC LIMIT 200`,
      req.query.status ? { status: req.query.status } : {},
    );
    res.json({ success: true, rides: rows });
  },
};
