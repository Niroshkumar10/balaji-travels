'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const pinoHttp = require('pino-http');
const logger = require('./infra/logger');
const env = require('./config/env');
const { apiLimiter } = require('./middleware/rateLimit');
const { notFound, errorHandler } = require('./middleware/error');
const v1 = require('./routes/v1');

function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(cors());

  // Capture the raw body so the admin HMAC middleware can verify a signature
  // over the exact bytes received.
  app.use(
    express.json({
      limit: '256kb',
      verify: (req, _res, buf) => {
        req.rawBody = buf.toString('utf8');
      },
    }),
  );

  app.use(
    pinoHttp({
      logger,
      autoLogging: { ignore: (req) => req.url === '/health' || req.url === '/' },
      customLogLevel: (_req, res, err) => (err || res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info'),
    }),
  );

  app.get('/health', (_req, res) => res.json({ status: 'ok', ts: Date.now() }));
  app.get('/', (_req, res) => res.json({ service: 'redtaxi-server', env: env.NODE_ENV }));

  app.use('/api', apiLimiter);
  app.use('/api/v1', v1);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}

module.exports = createApp;
