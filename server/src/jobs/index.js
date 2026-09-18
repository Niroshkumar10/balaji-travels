'use strict';

const offlineSweep = require('./offlineSweep');
const adminBookingAnnouncer = require('./adminBookingAnnouncer');
const scheduledDispatch = require('./scheduledDispatch');

function startJobs() {
  offlineSweep.start();
  adminBookingAnnouncer.start();
  scheduledDispatch.start();
}

function stopJobs() {
  offlineSweep.stop();
  adminBookingAnnouncer.stop();
  scheduledDispatch.stop();
}

module.exports = { startJobs, stopJobs };
