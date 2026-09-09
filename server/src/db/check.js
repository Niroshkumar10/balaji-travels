'use strict';

/**
 * Quick database connectivity check.  `npm run db:check`
 *
 * Prints the resolved connection target, then tries to connect and list the
 * RedTaxi tables. Exit code 0 = connected, 1 = not.
 */

const env = require('../config/env');
const db = require('../infra/db');

const redact = (s) => (s ? `${'*'.repeat(Math.min(s.length, 8))}` : '(empty)');

(async () => {
  console.log('Target:');
  console.log(`  host     ${env.DB_HOST}`);
  console.log(`  port     ${env.DB_PORT}`);
  console.log(`  user     ${env.DB_USER}`);
  console.log(`  password ${redact(env.DB_PASSWORD)}`);
  console.log(`  database ${env.DB_NAME}`);
  console.log('');

  try {
    await db.ping();
    const tables = await db.query(
      `SELECT table_name AS t FROM information_schema.tables
        WHERE table_schema = :db AND table_name LIKE 'rt\\_%'
        ORDER BY table_name`,
      { db: env.DB_NAME },
    );
    console.log(`✓ CONNECTED — ${tables.length} rt_* tables found`);
    if (tables.length) console.log('  ' + tables.map((r) => r.t).join(', '));

    const mig = await db
      .query(`SELECT name FROM rt_schema_migrations`)
      .catch(() => []);
    console.log(`  migrations recorded: ${mig.map((r) => r.name).join(', ') || '(none)'}`);
    process.exit(0);
  } catch (err) {
    console.error(`✗ NOT CONNECTED — ${err.code || ''} ${err.message}`);
    const hints = {
      ECONNREFUSED: 'Nothing is listening at that host:port. Wrong host, DB not running, or firewall.',
      ETIMEDOUT: 'Host unreachable — usually a firewall blocking port 3306 to your IP.',
      ENOTFOUND: 'Host name could not be resolved. Check DB_HOST.',
      ER_ACCESS_DENIED_ERROR: 'Wrong user/password, or the user is not allowed from your IP (add it in the panel\'s Remote MySQL).',
      ER_DBACCESS_DENIED_ERROR: 'User exists but has no rights on this database.',
      ER_BAD_DB_ERROR: 'The database name does not exist on that server.',
    };
    if (hints[err.code]) console.error(`  hint: ${hints[err.code]}`);
    process.exit(1);
  }
})();
