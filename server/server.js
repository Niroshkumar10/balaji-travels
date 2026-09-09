'use strict';

/**
 * Process entry point.
 *
 * The actual server — Express app, Socket.IO, background jobs, DB ping and
 * graceful shutdown — is defined in `src/server.js`. This top-level wrapper
 * exists only so the backend can be launched with `node server.js` from the
 * project root, as a process manager, Docker `CMD`, or a Webuzo / cPanel Node
 * app config expects.
 */

const logger = require('./src/infra/logger');
const { start } = require('./src/server');

start().catch((err) => {
  logger.error({ err }, 'failed to start');
  process.exit(1);
});
