'use strict';

const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const userRepo = require('../repositories/userRepo');
const customerRepo = require('../repositories/customerRepo');
const driverRepo = require('../repositories/driverRepo');
const vehicleRepo = require('../repositories/vehicleRepo');

const profileService = {
  async getCustomer(userId) {
    const [user, customer] = await Promise.all([
      userRepo.findById(userId),
      customerRepo.findByUserId(userId),
    ]);
    if (!user || !customer) throw ApiError.notFound('Customer profile not found');
    return {
      id: user.id,
      mobile: user.mobile,
      role: 'customer',
      name: user.name,
      email: user.email,
      customer,
    };
  },

  async updateCustomer(userId, patch) {
    await db.withTransaction(async (tx) => {
      const customer = await customerRepo.findByUserId(userId, tx);
      if (!customer) throw ApiError.notFound('Customer profile not found');
      await userRepo.updateProfile(userId, { name: patch.name, email: patch.email }, tx);
      await customerRepo.updateProfile(customer.id, patch, tx);
    });
    return this.getCustomer(userId);
  },

  async getDriver(userId) {
    const user = await userRepo.findById(userId);
    const driver = await driverRepo.findByUserId(userId);
    if (!user || !driver) throw ApiError.notFound('Driver profile not found');
    const vehicles = await vehicleRepo.listByDriver(driver.id);
    return {
      id: user.id,
      mobile: user.mobile,
      role: 'driver',
      name: user.name,
      email: user.email,
      driver,
      vehicles,
    };
  },

  async updateDriver(userId, patch) {
    await db.withTransaction(async (tx) => {
      const driver = await driverRepo.findByUserId(userId, tx);
      if (!driver) throw ApiError.notFound('Driver profile not found');
      await userRepo.updateProfile(userId, { name: patch.name, email: patch.email }, tx);
      await driverRepo.updateProfile(driver.id, { licenseNo: patch.licenseNo }, tx);
      if (patch.serviceTypes) await driverRepo.setServiceTypes(driver.id, patch.serviceTypes, tx);
    });
    return this.getDriver(userId);
  },

  async addVehicle(userId, vehicle) {
    return db.withTransaction(async (tx) => {
      const driver = await driverRepo.findByUserId(userId, tx);
      if (!driver) throw ApiError.notFound('Driver profile not found');
      const id = await vehicleRepo.create(driver.id, vehicle, tx);
      await vehicleRepo.setActiveForDriver(driver.id, id, tx);
      return vehicleRepo.findById(id, tx);
    });
  },

  async listVehicles(userId) {
    const driver = await driverRepo.findByUserId(userId);
    if (!driver) throw ApiError.notFound('Driver profile not found');
    return vehicleRepo.listByDriver(driver.id);
  },

  /** docType: 'license' | 'id_proof' | 'photo'. See drivers.routes.js for the validated shape. */
  async uploadDriverDocument(userId, { docType, number, expiry, idProofType, filename }) {
    const driver = await driverRepo.findByUserId(userId);
    if (!driver) throw ApiError.notFound('Driver profile not found');
    const patch = {};
    if (docType === 'license') {
      if (number !== undefined) patch.licenseNo = number;
      if (expiry !== undefined) patch.licenseExpiry = expiry;
      patch.licenseDocPath = filename;
    } else if (docType === 'id_proof') {
      if (idProofType !== undefined) patch.idProofType = idProofType;
      if (number !== undefined) patch.idProofNumber = number;
      patch.idProofDocPath = filename;
    } else if (docType === 'photo') {
      patch.photoPath = filename;
    } else {
      throw ApiError.badRequest('Unknown document type', 'INVALID_DOC_TYPE');
    }
    await driverRepo.updateDocuments(driver.id, patch);
    return this.getDriver(userId);
  },

  /** docType: 'rc' | 'insurance' | 'permit' | 'fitness' | 'puc'. */
  async uploadVehicleDocument(userId, { docType, number, expiry, filename }) {
    const driver = await driverRepo.findByUserId(userId);
    if (!driver) throw ApiError.notFound('Driver profile not found');
    const vehicle = driver.current_vehicle_id ? await vehicleRepo.findById(driver.current_vehicle_id) : null;
    if (!vehicle) throw ApiError.notFound('No vehicle on file for this driver yet — add a vehicle first');

    const prefix = { rc: 'rc', insurance: 'insurance', permit: 'permit', fitness: 'fitness', puc: 'puc' }[docType];
    if (!prefix) throw ApiError.badRequest('Unknown document type', 'INVALID_DOC_TYPE');

    const patch = {};
    if (number !== undefined) patch[`${prefix}Number`] = number;
    if (expiry !== undefined) patch[`${prefix}Expiry`] = expiry;
    patch[`${prefix}DocPath`] = filename;
    await vehicleRepo.updateDocuments(vehicle.id, patch);
    return vehicleRepo.findById(vehicle.id);
  },
};

module.exports = profileService;
