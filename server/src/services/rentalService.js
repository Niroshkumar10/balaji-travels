'use strict';

/**
 * Rental packages (hourly + included-km bundles) priced off the EXACT SAME
 * fare formula every other ride uses (fareService.quote against the live
 * rt_fare_configs row for a category) — no separate rental pricing table,
 * no invented formula. A package's quote is just quote({category,
 * distanceM: includedKm*1000, durationS: hours*3600}); the backend has no
 * per-vehicle-name pricing (Urbania/Tempo Traveller/Bus/...), so — same
 * honest tradeoff already made for Outstation's fleet list (see
 * trip_review_screen.dart's `_Fleet`) — a vehicle is mapped to the closest
 * real bike/auto/hatchback/sedan/suv category and priced as that category.
 */

const ApiError = require('../utils/apiError');
const fareService = require('./fareService');

const PACKAGE_HOURS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const KM_PER_HOUR = 10; // 1hr/10km, 2hr/20km, ... 10hr/100km

function includedKmFor(hours) {
  return hours * KM_PER_HOUR;
}

function isValidPackageHours(hours) {
  return PACKAGE_HOURS.includes(Number(hours));
}

const rentalService = {
  PACKAGE_HOURS,
  isValidPackageHours,
  includedKmFor,

  /** All 10 package tiers quoted for one vehicle category. */
  async quotePackages({ category }) {
    const packages = [];
    for (const hours of PACKAGE_HOURS) {
      const km = includedKmFor(hours);
      const q = await fareService.quote({
        category,
        distanceM: km * 1000,
        durationS: hours * 3600,
      });
      packages.push({ hours, includedKm: km, fare: q.total, currency: q.currency, breakdown: q.breakdown });
    }
    return packages;
  },

  /** Re-quotes one specific tier — used by createRide() so the charged fare
   * is always computed fresh server-side, never taken from what the
   * customer's app displayed earlier. */
  async quoteOnePackage({ category, hours }) {
    if (!isValidPackageHours(hours)) {
      throw ApiError.badRequest('Invalid rental package', 'INVALID_RENTAL_PACKAGE');
    }
    const km = includedKmFor(hours);
    const q = await fareService.quote({ category, distanceM: km * 1000, durationS: hours * 3600 });
    return { hours, includedKm: km, distanceM: km * 1000, durationS: hours * 3600, ...q };
  },
};

module.exports = rentalService;
