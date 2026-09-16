'use strict';

const offlineSweep = require('./offlineSweep');
const adminBookingAnnouncer = require('./adminBookingAnnouncer');

function startJobs() {
  offlineSweep.start();
  adminBookingAnnouncer.start();
}

function stopJobs() {
  offlineSweep.stop();
  adminBookingAnnouncer.stop();
}

module.exports = { startJobs, stopJobs };
