'use strict';

/**
 * In-process data store for DB_DRIVER=memory.
 *
 * Dev / demo / unit-test only — it exists so the OTP + profile flow can run
 * with zero external services (no MySQL, no Redis). It is NOT a SQL engine and
 * NOT wired into production; env.js forbids DB_DRIVER=memory when NODE_ENV is
 * production. The real persistence contract is database/schema.sql.
 *
 * Tables are plain arrays of row objects; each has an auto-incrementing `id`.
 */

const tables = {
  users: [],
  customers: [],
  drivers: [],
  vehicles: [],
  driver_wallet: [], // keyed by driver_id, no auto id
  otps: [],
};

const seqs = { users: 0, customers: 0, drivers: 0, vehicles: 0, otps: 0 };

function reset() {
  for (const k of Object.keys(tables)) tables[k] = [];
  for (const k of Object.keys(seqs)) seqs[k] = 0;
}

function insert(table, row) {
  const next = { ...row };
  if (table in seqs) {
    next.id = ++seqs[table];
  }
  const now = new Date().toISOString().slice(0, 19).replace('T', ' ');
  if (!('created_at' in next)) next.created_at = now;
  next.updated_at = now;
  tables[table].push(next);
  return next;
}

function all(table) {
  return tables[table];
}

function find(table, predicate) {
  return tables[table].find(predicate) ?? null;
}

function filter(table, predicate) {
  return tables[table].filter(predicate);
}

function update(row, patch) {
  Object.assign(row, patch, {
    updated_at: new Date().toISOString().slice(0, 19).replace('T', ' '),
  });
  return row;
}

module.exports = { tables, reset, insert, all, find, filter, update };
