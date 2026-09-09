'use strict';

const authService = require('../services/authService');

const authController = {
  async requestOtp(req, res) {
    const { mobile, role } = req.body;
    const result = await authService.requestOtp({ mobile, role });
    res.json({ success: true, ...result });
  },

  async verifyOtp(req, res) {
    const { mobile, role, code } = req.body;
    const result = await authService.verifyOtp({ mobile, role, code });
    res.json({ success: true, ...result });
  },

  async logout(req, res) {
    await authService.logout(req.auth.userId, req.auth.role);
    res.json({ success: true });
  },

  async registerFcmToken(req, res) {
    await authService.registerFcmToken(req.auth.userId, req.body.fcmToken);
    res.json({ success: true });
  },

  async me(req, res) {
    // Lightweight identity echo — full profile lives under /customers/me or
    // /drivers/me (added in Phase 2 continuation).
    res.json({ success: true, auth: req.auth });
  },
};

module.exports = authController;
