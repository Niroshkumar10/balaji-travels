'use strict';

/**
 * Geometry + routing helpers.
 *
 * Distance / duration / polyline come from Google (Directions + Distance Matrix)
 * when GOOGLE_MAPS_SERVER_KEY is set — the key lives ONLY here, server-side,
 * never in the apps. With no key (local dev), `route()` falls back to a
 * straight-line estimate scaled by a road factor + an assumed average speed, so
 * the whole ride flow still works offline.
 */

const env = require('../config/env');
const logger = require('../infra/logger');

const EARTH_KM = 6371;
const ROAD_FACTOR = 1.35; // straight-line → approx road distance
const AVG_SPEED_KMPH = 24; // urban assumption for the fallback ETA

function toRad(d) {
  return (d * Math.PI) / 180;
}

/** Great-circle distance in metres. */
function haversineMeters(aLat, aLng, bLat, bLng) {
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(EARTH_KM * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s)) * 1000);
}

/**
 * Bounding box (deg) around a point for a coarse SQL pre-filter before the
 * exact Haversine sort.
 */
function boundingBox(lat, lng, radiusKm) {
  const latDelta = radiusKm / 111.32;
  const lngDelta = radiusKm / (111.32 * Math.max(0.01, Math.cos(toRad(lat))));
  return {
    latMin: lat - latDelta,
    latMax: lat + latDelta,
    lngMin: lng - lngDelta,
    lngMax: lng + lngDelta,
  };
}

/**
 * @returns {Promise<{ distanceM:number, durationS:number, polyline:string|null, source:'google'|'estimate' }>}
 */
async function route(pickup, drop) {
  if (env.GOOGLE_MAPS_SERVER_KEY) {
    try {
      const url =
        `https://maps.googleapis.com/maps/api/directions/json` +
        `?origin=${pickup.lat},${pickup.lng}&destination=${drop.lat},${drop.lng}` +
        `&mode=driving&key=${env.GOOGLE_MAPS_SERVER_KEY}`;
      const res = await fetch(url);
      const body = await res.json();
      const leg = body?.routes?.[0]?.legs?.[0];
      if (leg) {
        return {
          distanceM: leg.distance.value,
          durationS: leg.duration.value,
          polyline: body.routes[0].overview_polyline?.points ?? null,
          source: 'google',
        };
      }
      logger.warn({ status: body?.status }, 'directions returned no route — using estimate');
    } catch (err) {
      logger.warn({ err: err.message }, 'directions call failed — using estimate');
    }
  }

  const straight = haversineMeters(pickup.lat, pickup.lng, drop.lat, drop.lng);
  const distanceM = Math.round(straight * ROAD_FACTOR);
  const durationS = Math.round((distanceM / 1000 / AVG_SPEED_KMPH) * 3600);
  return { distanceM, durationS, polyline: null, source: 'estimate' };
}

/** Rough ETA in seconds for a driver at `from` to reach `to` (fallback speed). */
function etaSeconds(from, to) {
  const m = haversineMeters(from.lat, from.lng, to.lat, to.lng) * ROAD_FACTOR;
  return Math.round((m / 1000 / AVG_SPEED_KMPH) * 3600);
}

module.exports = { haversineMeters, boundingBox, route, etaSeconds, ROAD_FACTOR, AVG_SPEED_KMPH };
