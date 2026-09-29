'use strict';

/**
 * Driver presence — the "am I available for rides" state.
 *
 * A driver may go online only if: KYC approved, has an active vehicle, and is
 * not already on a trip. `availability` here only ever moves offline↔available;
 * 'on_trip' is owned exclusively by the atomic ride-assignment path so it can
 * never be clobbered by a stray heartbeat.
 */

const db = require('../infra/db');
const L = require('../infra/logger').for('presence'); // → logs/presence.log
const ApiError = require('../utils/apiError');
const driverRepo = require('../repositories/driverRepo');
const vehicleRepo = require('../repositories/vehicleRepo');
const driverLocationRepo = require('../repositories/driverLocationRepo');
const rideRepo = require('../repositories/rideRepo');

const presenceService = {
  async goOnline(driverId, { lat, lng }) {
    const driver = await driverRepo.findById(driverId);
    if (!driver) throw ApiError.notFound('Driver not found');
    if (driver.kyc_status !== 'approved') {
      throw ApiError.forbidden('KYC not approved — cannot go online', 'KYC_NOT_APPROVED');
    }
    const vehicles = await vehicleRepo.listByDriver(driverId); // not deleted, id DESC
    if (vehicles.length === 0) {
      throw ApiError.badRequest('Add a vehicle before going online', 'NO_ACTIVE_VEHICLE');
    }

    // Dispatch takes the driver's category from the vehicle that
    // rt_drivers.current_vehicle_id points at — and only when that vehicle is
    // active, not soft-deleted, and owned by this driver. Reconcile that pairing
    // before entering the pool: keep the driver's chosen current vehicle if it's
    // still valid, otherwise fall back to the most recently added one, and make
    // it the sole active vehicle. Prevents "online but never matched".
    const chosen =
      vehicles.find((v) => v.id === driver.current_vehicle_id) ?? vehicles[0];
    const pairingOk =
      driver.current_vehicle_id === chosen.id &&
      !!chosen.is_active &&
      !vehicles.some((v) => v.is_active && v.id !== chosen.id);

    if (driver.availability === 'on_trip' || driver.availability === 'reserved') {
      // Already holding a ride (live, or a future reservation) — just
      // refresh location and confirm online; skip vehicle-pairing
      // reconciliation (not the moment to reconcile a vehicle swap mid-hold)
      // and don't force back to 'available' — recomputeAvailability would
      // correctly re-derive on_trip/reserved from rt_rides anyway, but
      // there's nothing that changed here for it to reconcile.
      await driverLocationRepo.upsert(driverId, { lat, lng });
      await driverRepo.setPresence(driverId, { isOnline: true, availability: driver.availability });
      return { availability: driver.availability };
    }
    await db.withTransaction(async (tx) => {
      if (!pairingOk) {
        await vehicleRepo.setActiveForDriver(driverId, chosen.id, tx);
        L.event('🚗', 'reconciled current vehicle on go-online', {
          driverId,
          vehicleId: chosen.id,
          category: chosen.category,
        });
      }
      await driverRepo.setPresence(driverId, { isOnline: true, availability: 'available' }, tx);
      await driverLocationRepo.upsert(driverId, { lat, lng }, tx);
    });
    L.event('🟢', 'driver went ONLINE', { driverId, lat, lng });
    return { availability: 'available' };
  },

  async goOffline(driverId) {
    // findActiveForDriver() only ever returns the ONE ride currently
    // occupying the driver's exclusive active_driver_id slot (see migration
    // 0004) — a driver holding only a future, not-yet-started Rental/Trip
    // reservation is free to go offline (e.g. overnight); the reservation
    // survives in rt_rides and is restored via recomputeAvailability() the
    // next time they go online.
    const active = await rideRepo.findActiveForDriver(driverId);
    if (active) {
      throw ApiError.conflict('Finish or cancel your active ride before going offline', 'HAS_ACTIVE_RIDE');
    }
    await driverRepo.setPresence(driverId, { isOnline: false, availability: 'offline' });
    L.event('🔴', 'driver went OFFLINE', { driverId });
    return { availability: 'offline' };
  },

  /** Heartbeat / location ping while idle-online. Does not touch availability. */
  async heartbeat(driverId, { lat, lng, bearing, speedKmph, battery }) {
    await driverLocationRepo.upsert(driverId, { lat, lng, bearing, speedKmph, battery });
    await driverRepo.touchLastSeen(driverId);
    L.debug({ driverId, lat, lng }, 'heartbeat');
  },
};

module.exports = presenceService;
