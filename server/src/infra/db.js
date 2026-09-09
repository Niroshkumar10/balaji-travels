'use strict';

/**
 * Database access.
 *
 * DB_DRIVER=mysql  → a single mysql2 promise pool + a uniform query interface
 *                    that is identical on the pool and inside a transaction.
 * DB_DRIVER=memory → no pool is opened; `withTransaction` just runs the fn
 *                    (repositories switch to the in-process memoryStore). Dev /
 *                    demo / test only — forbidden in production by env.js.
 *
 * Design notes (carried from the Microlab load-test findings):
 *  - Pool size is env-driven (DB_POOL_SIZE), not hard-coded. A too-small pool
 *    + one slow query stalls unrelated requests even at low DB CPU.
 *  - `withTransaction(fn)` is the ONLY sanctioned way to do a multi-statement
 *    write. Correctness-critical writes go through it — never fire-and-forget.
 *  - Parameterised only (named placeholders). No string interpolation of user
 *    input into SQL anywhere in this codebase.
 */

const env = require('../config/env');
const logger = require('./logger');

const MEMORY = env.DB_DRIVER === 'memory';

let pool = null;
let makeApi = null;

if (!MEMORY) {
  const mysql = require('mysql2/promise');
  pool = mysql.createPool({
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    connectionLimit: env.DB_POOL_SIZE,
    waitForConnections: true,
    queueLimit: 0,
    enableKeepAlive: true,
    keepAliveInitialDelay: 10_000,
    namedPlaceholders: true,
    timezone: 'Z',
    dateStrings: true,
    charset: 'utf8mb4',
  });

  makeApi = (executor) => ({
    async query(sql, params = {}) {
      const [rows] = await executor.query(sql, params);
      return rows;
    },
    async execute(sql, params = {}) {
      const [rows] = await executor.execute(sql, params);
      return rows;
    },
    async queryOne(sql, params = {}) {
      const [rows] = await executor.query(sql, params);
      return rows[0] ?? null;
    },
  });
}

// In memory mode this is the "context" object repos receive; they ignore it.
const memoryTx = { memory: true };

const api = MEMORY
  ? {
      query: async () => {
        throw new Error('db.query is unavailable in DB_DRIVER=memory mode');
      },
      execute: async () => {
        throw new Error('db.execute is unavailable in DB_DRIVER=memory mode');
      },
      queryOne: async () => {
        throw new Error('db.queryOne is unavailable in DB_DRIVER=memory mode');
      },
    }
  : makeApi(pool);

/**
 * Transactional unit of work. `fn` gets a db-like context bound to a dedicated
 * connection (mysql) or a passthrough marker (memory). Commits on success,
 * rolls back on any throw, always releases.
 * @template T
 * @param {(tx: any) => Promise<T>} fn
 * @returns {Promise<T>}
 */
async function withTransaction(fn) {
  if (MEMORY) return fn(memoryTx);

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(makeApi(conn));
    await conn.commit();
    return result;
  } catch (err) {
    try {
      await conn.rollback();
    } catch (rollbackErr) {
      logger.error({ err: rollbackErr }, 'transaction rollback failed');
    }
    throw err;
  } finally {
    conn.release();
  }
}

async function ping() {
  if (MEMORY) return;
  const conn = await pool.getConnection();
  try {
    await conn.ping();
  } finally {
    conn.release();
  }
}

async function close() {
  if (pool) await pool.end();
}

module.exports = {
  MEMORY,
  pool,
  query: api.query,
  execute: api.execute,
  queryOne: api.queryOne,
  withTransaction,
  ping,
  close,
};
