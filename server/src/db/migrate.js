'use strict';

/**
 * Minimal forward-only SQL migration runner.
 *
 *   node src/db/migrate.js up        apply every pending migration
 *   node src/db/migrate.js status    list applied / pending
 *   node src/db/migrate.js down      roll back the most recent (needs a .down.sql)
 *
 * Migrations live in src/db/migrations as `NNNN_name.sql` (and optional
 * `NNNN_name.down.sql`). Applied migrations are recorded in
 * `rt_schema_migrations` so re-running `up` is a no-op.
 */

const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const env = require('../config/env');

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

async function getConn() {
  return mysql.createConnection({
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    multipleStatements: true,
  });
}

async function ensureTable(conn) {
  await conn.query(`
    CREATE TABLE IF NOT EXISTS rt_schema_migrations (
      name       VARCHAR(255) NOT NULL,
      applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);
}

function listMigrationFiles() {
  return fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql') && !f.endsWith('.down.sql'))
    .sort();
}

async function appliedSet(conn) {
  const [rows] = await conn.query('SELECT name FROM rt_schema_migrations');
  return new Set(rows.map((r) => r.name));
}

async function up() {
  const conn = await getConn();
  try {
    await ensureTable(conn);
    const applied = await appliedSet(conn);
    const files = listMigrationFiles();
    const pending = files.filter((f) => !applied.has(f));

    if (pending.length === 0) {
      console.log('✓ nothing to migrate — schema up to date');
      return;
    }

    for (const file of pending) {
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      console.log(`→ applying ${file}`);
      await conn.query('START TRANSACTION');
      try {
        await conn.query(sql);
        await conn.query('INSERT INTO rt_schema_migrations (name) VALUES (?)', [file]);
        await conn.query('COMMIT');
        console.log(`  ✓ ${file}`);
      } catch (err) {
        await conn.query('ROLLBACK');
        console.error(`  ✗ ${file} failed — rolled back\n`, err.message);
        process.exitCode = 1;
        return;
      }
    }
    console.log(`✓ applied ${pending.length} migration(s)`);
  } finally {
    await conn.end();
  }
}

async function status() {
  const conn = await getConn();
  try {
    await ensureTable(conn);
    const applied = await appliedSet(conn);
    for (const file of listMigrationFiles()) {
      console.log(`${applied.has(file) ? '[x]' : '[ ]'} ${file}`);
    }
  } finally {
    await conn.end();
  }
}

async function down() {
  const conn = await getConn();
  try {
    await ensureTable(conn);
    const [rows] = await conn.query(
      'SELECT name FROM rt_schema_migrations ORDER BY name DESC LIMIT 1',
    );
    if (rows.length === 0) {
      console.log('nothing to roll back');
      return;
    }
    const name = rows[0].name;
    const downFile = name.replace(/\.sql$/, '.down.sql');
    const downPath = path.join(MIGRATIONS_DIR, downFile);
    if (!fs.existsSync(downPath)) {
      console.error(`✗ no down migration found: ${downFile}`);
      process.exitCode = 1;
      return;
    }
    const sql = fs.readFileSync(downPath, 'utf8');
    console.log(`→ rolling back ${name}`);
    await conn.query('START TRANSACTION');
    try {
      await conn.query(sql);
      await conn.query('DELETE FROM rt_schema_migrations WHERE name = ?', [name]);
      await conn.query('COMMIT');
      console.log(`✓ rolled back ${name}`);
    } catch (err) {
      await conn.query('ROLLBACK');
      console.error(`✗ rollback failed\n`, err.message);
      process.exitCode = 1;
    }
  } finally {
    await conn.end();
  }
}

const cmd = process.argv[2] || 'up';
const run = { up, down, status }[cmd];
if (!run) {
  console.error(`unknown command: ${cmd}\nusage: migrate.js [up|down|status]`);
  process.exit(1);
}
run().catch((err) => {
  console.error(err);
  process.exit(1);
});
