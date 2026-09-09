'use strict';

const { ZodError } = require('zod');
const ApiError = require('../utils/apiError');
const logger = require('../infra/logger');
const env = require('../config/env');

/** 404 for any unmatched route. */
function notFound(req, res, next) {
  next(ApiError.notFound(`Route not found: ${req.method} ${req.originalUrl}`, 'ROUTE_NOT_FOUND'));
}

/* eslint-disable no-unused-vars */
/** Central error handler — the single place a response error shape is decided. */
function errorHandler(err, req, res, next) {
  // Zod validation errors → 400 with field details.
  if (err instanceof ZodError) {
    return res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Request validation failed',
        details: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      },
    });
  }

  // Known DB integrity errors → 409 instead of a leaked 500.
  if (err && err.code === 'ER_DUP_ENTRY') {
    logger.warn({ err: err.message }, 'duplicate key');
    return res.status(409).json({ error: { code: 'DUPLICATE', message: 'Resource already exists' } });
  }

  if (err instanceof ApiError) {
    if (!err.expose) logger.error({ err }, 'internal ApiError');
    return res.status(err.status).json({
      error: { code: err.code, message: err.expose ? err.message : 'Internal server error', ...(err.details ? { details: err.details } : {}) },
    });
  }

  // Anything else is unexpected — log the full thing, tell the client nothing.
  logger.error({ err, path: req.originalUrl, method: req.method }, 'unhandled error');
  return res.status(500).json({
    error: {
      code: 'INTERNAL',
      message: 'Internal server error',
      ...(env.isProd ? {} : { debug: err.message }),
    },
  });
}

module.exports = { notFound, errorHandler };
