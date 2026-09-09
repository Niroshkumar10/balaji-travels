'use strict';

const offlineSweep = require('./offlineSweep');

function startJobs() {
  offlineSweep.start();
}

function stopJobs() {
  offlineSweep.stop();
}

module.exports = { startJobs, stopJobs };
