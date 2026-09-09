'use strict';

/**
 * The mysql2 pool is configured with `timezone: 'Z'` + `dateStrings: true`, so
 * DATETIME columns are stored and returned as UTC wall-clock strings like
 * "2026-09-08 06:26:27" — with NO timezone marker. `new Date(thatString)` would
 * parse it as *local* time. `parseUtc` forces the correct UTC interpretation,
 * and is used identically for the in-memory driver (which stores the same
 * format) so both paths agree.
 */
function parseUtc(value) {
  if (value == null) return null;
  if (value instanceof Date) return value;
  const s = String(value).trim();
  // already has an explicit offset / Z
  if (/[zZ]$|[+-]\d{2}:?\d{2}$/.test(s)) return new Date(s);
  return new Date(s.replace(' ', 'T') + 'Z');
}

/** Current time as a MySQL-style UTC DATETIME string. */
function utcNowString(offsetMs = 0) {
  return new Date(Date.now() + offsetMs).toISOString().slice(0, 19).replace('T', ' ');
}

module.exports = { parseUtc, utcNowString };
