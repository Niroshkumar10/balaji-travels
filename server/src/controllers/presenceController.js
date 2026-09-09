'use strict';

const presenceService = require('../services/presenceService');

module.exports = {
  async goOnline(req, res) {
    const out = await presenceService.goOnline(req.auth.profileId, {
      lat: req.body.lat,
      lng: req.body.lng,
    });
    res.json({ success: true, ...out });
  },
  async goOffline(req, res) {
    res.json({ success: true, ...(await presenceService.goOffline(req.auth.profileId)) });
  },
  async heartbeat(req, res) {
    await presenceService.heartbeat(req.auth.profileId, req.body);
    res.json({ success: true });
  },
};
