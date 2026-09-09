'use strict';

/**
 * Structured logger (pino).
 *
 * - Pretty, colourised output in dev; single-line JSON in prod/test.
 * - `redact` strips anything that must never reach a log line — tokens, OTPs,
 *   passwords, auth headers, gateway secrets — at every nesting level.
 */

const pino = require('pino');
const env = require('../config/env');

const redactPaths = [
  'req.headers.authorization',
  'req.headers.cookie',
  '*.token',
  '*.accessToken',
  '*.auth_token',
  '*.password',
  '*.otp',
  '*.code',
  '*.code_hash',
  '*.jwt',
  '*.secret',
  '*.key_secret',
  '*.RAZORPAY_KEY_SECRET',
  'headers.authorization',
];

const logger = pino({
  level: env.isTest ? 'silent' : env.isProd ? 'info' : 'debug',
  redact: { paths: redactPaths, censor: '[redacted]' },
  base: { service: 'redtaxi-server' },
  timestamp: pino.stdTimeFunctions.isoTime,
  transport: env.isDev
    ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'HH:MM:ss.l', ignore: 'pid,hostname,service' } }
    : undefined,
});

module.exports = logger;
