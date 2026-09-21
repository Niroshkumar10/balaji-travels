'use strict';

/**
 * Shared time-window math for "does this ride occupy the same span of time
 * as that one" — used by rideService.js's customer multi-booking conflict
 * check and dispatchService.js's driver time-aware availability check
 * (admin-assigned Rental/Outstation/Round Trip). One copy, so the tricky
 * part below only has to be gotten right once.
 */

// Fallback only — every ride's duration_s is set at creation (real route
// duration for local/outstation/round_trip, hours*3600 for rental), so this
// should never actually be hit in practice.
const DEFAULT_RIDE_DURATION_S = 2 * 60 * 60;

// db.js's pool is configured `timezone: 'Z'` + `dateStrings: true` — every
// DATETIME comes back as a plain "YYYY-MM-DD HH:mm:ss" string that IS a UTC
// instant but carries no marker saying so. `new Date()` on a string like
// that parses it as LOCAL time, which silently shifts it by the server's
// UTC offset (5:30 in IST) — wrong instant, and specifically wrong in the
// direction that makes two genuinely-overlapping windows look like they
// don't overlap. Existing/requested timestamps read back from the DB MUST
// go through this, not a bare `new Date(...)`; scheduledAt from an incoming
// request is already a real Date/ISO string (via zod's z.coerce.date()) and
// is exempt — only round-tripped DB strings have this problem.
function parseDbTimestampUtc(s) {
  if (!s) return null;
  return s instanceof Date ? s : new Date(`${String(s).replace(' ', 'T')}Z`);
}

/** [start, end) epoch-ms window a ride occupies, for conflict checking. */
function rideWindow(startMs, durationS) {
  const start = startMs;
  const end = start + (durationS ?? DEFAULT_RIDE_DURATION_S) * 1000;
  return { start, end };
}

const windowsOverlap = (a, b) => a.start < b.end && b.start < a.end;

/** A ride row's own occupied window — DB-sourced scheduled_at/requested_at. */
function windowForRideRow(row) {
  const start = row.scheduled_at
    ? parseDbTimestampUtc(row.scheduled_at).getTime()
    : parseDbTimestampUtc(row.requested_at).getTime();
  return rideWindow(start, row.duration_s);
}

module.exports = { DEFAULT_RIDE_DURATION_S, parseDbTimestampUtc, rideWindow, windowsOverlap, windowForRideRow };
