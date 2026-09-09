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
};

module.exports = profileService;
