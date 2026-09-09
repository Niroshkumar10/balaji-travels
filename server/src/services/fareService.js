'use strict';

/**
 * Backend-authoritative fare.
 *
 * The apps may show an ESTIMATE (via /rides/estimate), but the payable amount
 * is ALWAYS computed here from real distance/time + the active rt_fare_configs
 * row. A client-supplied fare is never trusted or stored.
 *
 *   fare = max(min_fare,
 *              base_fare
 *            + per_km * max(0, distanceKm - included_km)
 *            + per_min * durationMin
 *            + waiting_per_min * max(0, waitingMin - free_waiting_min))
 *          * surge_multiplier
 *          * (nightWindow ? night_multiplier : 1)
 *        − promoDiscount            (never below 0)
 */

const ApiError = require('../utils/apiError');
const fareConfigRepo = require('../repositories/fareConfigRepo');

const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

function isNightNow(cfg, when = new Date()) {
  if (!cfg.night_start || !cfg.night_end) return false;
  const hm = `${String(when.getHours()).padStart(2, '0')}:${String(when.getMinutes()).padStart(2, '0')}:00`;
  const start = String(cfg.night_start);
  const end = String(cfg.night_end);
  // window may wrap past midnight (e.g. 23:00 → 05:00)
  return start <= end ? hm >= start && hm < end : hm >= start || hm < end;
}

/**
 * @param {object} p
 * @param {'bike'|'auto'|'hatchback'|'sedan'|'suv'} p.category
 * @param {number} p.distanceM
 * @param {number} p.durationS
 * @param {number} [p.waitingMin=0]
 * @param {string} [p.zone='default']
 * @param {number} [p.promoDiscount=0]
 * @param {Date}   [p.when]
 * @returns {Promise<{ currency:string, total:number, breakdown:object, config_id:number }>}
 */
async function quote(p) {
  const cfg = await fareConfigRepo.forCategory(p.category, p.zone ?? 'default');
  if (!cfg) throw ApiError.badRequest(`No fare configuration for '${p.category}'`, 'NO_FARE_CONFIG');

  const distanceKm = (p.distanceM ?? 0) / 1000;
  const durationMin = (p.durationS ?? 0) / 60;
  const waitingMin = p.waitingMin ?? 0;

  const base = Number(cfg.base_fare);
  const distanceCharge = Number(cfg.per_km) * Math.max(0, distanceKm - Number(cfg.included_km));
  const timeCharge = Number(cfg.per_min) * durationMin;
  const waitingCharge =
    Number(cfg.waiting_per_min) * Math.max(0, waitingMin - Number(cfg.free_waiting_min));

  let subtotal = base + distanceCharge + timeCharge + waitingCharge;
  subtotal = Math.max(subtotal, Number(cfg.min_fare));

  const surge = Number(cfg.surge_multiplier) || 1;
  const night = isNightNow(cfg, p.when) ? Number(cfg.night_multiplier) || 1 : 1;
  const beforeDiscount = subtotal * surge * night;

  const promoDiscount = Math.max(0, Math.min(p.promoDiscount ?? 0, beforeDiscount));
  const total = round2(Math.max(0, beforeDiscount - promoDiscount));

  return {
    currency: 'INR',
    total,
    config_id: cfg.id,
    breakdown: {
      base: round2(base),
      distance_km: round2(distanceKm),
      distance_charge: round2(distanceCharge),
      time_min: round2(durationMin),
      time_charge: round2(timeCharge),
      waiting_min: waitingMin,
      waiting_charge: round2(waitingCharge),
      min_fare_applied: subtotal === Number(cfg.min_fare),
      surge_multiplier: surge,
      night_multiplier: night,
      before_discount: round2(beforeDiscount),
      promo_discount: round2(promoDiscount),
      total,
    },
  };
}

module.exports = { quote, isNightNow, round2 };
