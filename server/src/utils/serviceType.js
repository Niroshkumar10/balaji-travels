'use strict';

const SERVICE_TYPES = ['local', 'rental', 'outstation'];

// round_trip is an outstation booking that also returns — same driver pool.
const RIDE_TYPE_TO_SERVICE = {
  local: 'local',
  outstation: 'outstation',
  round_trip: 'outstation',
  rental: 'rental',
};

function serviceFor(rideType) {
  return RIDE_TYPE_TO_SERVICE[rideType] ?? 'local';
}

/** rt_drivers.service_types comes back from MySQL as "local,outstation". */
function parseServiceTypes(value) {
  if (Array.isArray(value)) return value;
  if (!value) return [];
  return String(value)
    .split(',')
    .map((s) => s.trim())
    .filter((s) => SERVICE_TYPES.includes(s));
}

function driverServes(driver, rideType) {
  return parseServiceTypes(driver?.service_types).includes(serviceFor(rideType));
}

module.exports = { SERVICE_TYPES, serviceFor, parseServiceTypes, driverServes };
