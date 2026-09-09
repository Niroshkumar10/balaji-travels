'use strict';

/**
 * Places search + geocoding, proxied server-side so GOOGLE_MAPS_SERVER_KEY
 * never ships in the apps. With no key, returns a small offline-friendly
 * response so the UI still functions in dev.
 */

const env = require('../config/env');
const logger = require('../infra/logger');
const savedPlaceRepo = require('../repositories/savedPlaceRepo');

async function autocomplete(query, { lat, lng } = {}) {
  if (!env.GOOGLE_MAPS_SERVER_KEY) {
    return [{ description: query, placeId: null, note: 'geocoding disabled (no server key)' }];
  }
  const loc = lat != null && lng != null ? `&location=${lat},${lng}&radius=30000` : '';
  const url =
    `https://maps.googleapis.com/maps/api/place/autocomplete/json` +
    `?input=${encodeURIComponent(query)}${loc}&key=${env.GOOGLE_MAPS_SERVER_KEY}`;
  try {
    const res = await fetch(url);
    const body = await res.json();
    return (body.predictions ?? []).map((p) => ({
      description: p.description,
      placeId: p.place_id,
      mainText: p.structured_formatting?.main_text,
      secondaryText: p.structured_formatting?.secondary_text,
    }));
  } catch (err) {
    logger.warn({ err: err.message }, 'places autocomplete failed');
    return [];
  }
}

async function geocode(placeId) {
  if (!env.GOOGLE_MAPS_SERVER_KEY) return null;
  const url =
    `https://maps.googleapis.com/maps/api/place/details/json` +
    `?place_id=${encodeURIComponent(placeId)}&fields=geometry,formatted_address&key=${env.GOOGLE_MAPS_SERVER_KEY}`;
  const res = await fetch(url);
  const body = await res.json();
  const g = body.result?.geometry?.location;
  return g ? { lat: g.lat, lng: g.lng, addr: body.result.formatted_address } : null;
}

async function reverseGeocode(lat, lng) {
  if (!env.GOOGLE_MAPS_SERVER_KEY) {
    return { lat, lng, addr: `${lat.toFixed(5)}, ${lng.toFixed(5)}` };
  }
  const url =
    `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${env.GOOGLE_MAPS_SERVER_KEY}`;
  const res = await fetch(url);
  const body = await res.json();
  const first = body.results?.[0];
  return { lat, lng, addr: first?.formatted_address ?? `${lat}, ${lng}` };
}

module.exports = {
  autocomplete,
  geocode,
  reverseGeocode,
  listSaved: (customerId) => savedPlaceRepo.list(customerId),
  addSaved: (customerId, p) => savedPlaceRepo.create(customerId, p),
  removeSaved: (customerId, id) => savedPlaceRepo.remove(customerId, id),
};
