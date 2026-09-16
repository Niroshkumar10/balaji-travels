'use strict';

const profileService = require('../services/profileService');
const ApiError = require('../utils/apiError');

module.exports = {
  async getCustomerMe(req, res) {
    res.json({ success: true, profile: await profileService.getCustomer(req.auth.userId) });
  },
  async patchCustomerMe(req, res) {
    res.json({ success: true, profile: await profileService.updateCustomer(req.auth.userId, req.body) });
  },
  async getDriverMe(req, res) {
    res.json({ success: true, profile: await profileService.getDriver(req.auth.userId) });
  },
  async patchDriverMe(req, res) {
    res.json({ success: true, profile: await profileService.updateDriver(req.auth.userId, req.body) });
  },
  async addVehicle(req, res) {
    res.status(201).json({ success: true, vehicle: await profileService.addVehicle(req.auth.userId, req.body) });
  },
  async listVehicles(req, res) {
    res.json({ success: true, vehicles: await profileService.listVehicles(req.auth.userId) });
  },
  async uploadDriverDocument(req, res) {
    if (!req.file) throw ApiError.badRequest('No file uploaded', 'NO_FILE');
    const profile = await profileService.uploadDriverDocument(req.auth.userId, {
      ...req.body,
      filename: req.file.filename,
    });
    res.status(201).json({ success: true, profile });
  },
  async uploadVehicleDocument(req, res) {
    if (!req.file) throw ApiError.badRequest('No file uploaded', 'NO_FILE');
    const vehicle = await profileService.uploadVehicleDocument(req.auth.userId, {
      ...req.body,
      filename: req.file.filename,
    });
    res.status(201).json({ success: true, vehicle });
  },
};
