'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const pinoHttp = require('pino-http');
const logger = require('./infra/logger');
const env = require('./config/env');
const { apiLimiter } = require('./middleware/rateLimit');
const { notFound, errorHandler } = require('./middleware/error');
const { UPLOAD_ROOT } = require('./middleware/upload');
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

  // Uploaded KYC documents (driver license/ID/photo, vehicle RC/insurance/
  // permit/fitness/PUC) — served as plain static files so both this app and
  // the separate Admin Panel can display them by the doc_path stored in
  // rt_drivers/rt_vehicles. Helmet's default cross-origin-resource-policy is
  // same-origin, which would block the Admin Panel (a different origin) from
  // loading these images — relaxed only for this one static mount.
  app.use(
    '/uploads',
    (req, res, next) => {
      res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
      next();
    },
    express.static(UPLOAD_ROOT),
  );

  app.use('/api', apiLimiter);
  app.use('/api/v1', v1);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}

module.exports = createApp;
