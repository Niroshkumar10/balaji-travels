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
const logger = require('../infra/logger');
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
    const vehicles = await vehicleRepo.listByDriver(driverId);
    if (!vehicles.some((v) => v.is_active)) {
      throw ApiError.badRequest('Add an active vehicle before going online', 'NO_ACTIVE_VEHICLE');
    }
    if (driver.availability === 'on_trip') {
      // already mid-trip — just refresh location, stay on_trip
      await driverLocationRepo.upsert(driverId, { lat, lng });
      return { availability: 'on_trip' };
    }
    await db.withTransaction(async (tx) => {
      await driverRepo.setPresence(driverId, { isOnline: true, availability: 'available' }, tx);
      await driverLocationRepo.upsert(driverId, { lat, lng }, tx);
    });
    logger.info({ driverId, lat, lng }, 'presence.online');
    return { availability: 'available' };
  },

  async goOffline(driverId) {
    const active = await rideRepo.findActiveForDriver(driverId);
    if (active) {
      throw ApiError.conflict('Finish or cancel your active ride before going offline', 'HAS_ACTIVE_RIDE');
    }
    await driverRepo.setPresence(driverId, { isOnline: false, availability: 'offline' });
    logger.info({ driverId }, 'presence.offline');
    return { availability: 'offline' };
  },

  /** Heartbeat / location ping while idle-online. Does not touch availability. */
  async heartbeat(driverId, { lat, lng, bearing, speedKmph, battery }) {
    await driverLocationRepo.upsert(driverId, { lat, lng, bearing, speedKmph, battery });
    await driverRepo.touchLastSeen(driverId);
    logger.debug({ driverId, lat, lng }, 'presence.heartbeat');
  },
};

module.exports = presenceService;
