'use strict';

const http = require('http');
const env = require('./src/config/env');
const logger = require('./src/infra/logger');
const db = require('./src/infra/db');
const createApp = require('./src/app');
const { initSockets } = require('./src/sockets');
const { startJobs, stopJobs } = require('./src/jobs');

// A thrown error in a timer/async callback must never take the whole process
// down silently (Microlab load-test finding: an uncaught throw inside a
// setTimeout in the dispatch path killed the server for every connected user).
process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'unhandledRejection');
});
process.on('uncaughtException', (err) => {
  logger.error({ err }, 'uncaughtException — staying up; investigate');
});

async function start() {
  if (env.isProd && env.OTP_EXPOSE_CODE) {
    logger.warn(
      'OTP_EXPOSE_CODE=true in production — OTP codes are returned in API responses. Testing only; turn this off once SMS works.',
    );
  }

  await db.ping();
  logger.info('database reachable');

  const app = createApp();
  const server = http.createServer(app);
  initSockets(server);
  startJobs();

  server.listen(env.PORT, () => {
    logger.info(`RedTaxi server listening on :${env.PORT} (${env.NODE_ENV})`);
  });

  const shutdown = async (signal) => {
    logger.info({ signal }, 'shutting down');
    stopJobs();
    server.close();
    await Promise.allSettled([db.close()]);
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  return server;
}

if (require.main === module) {
  start().catch((err) => {
    logger.error({ err }, 'failed to start');
    process.exit(1);
  });
}

module.exports = { start };
