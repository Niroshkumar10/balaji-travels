'use strict';

/**
 * Typed application error. Thrown anywhere in a service/controller; the central
 * error middleware turns it into `{ error: { code, message, details? } }` with
 * the right HTTP status. `expose` distinguishes "safe to show the client" from
 * "internal — log it, send a generic message".
 */
class ApiError extends Error {
  constructor(status, code, message, details = undefined) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
    this.expose = status < 500;
  }

  static badRequest(msg = 'Bad request', code = 'BAD_REQUEST', details) {
    return new ApiError(400, code, msg, details);
  }
  static unauthorized(msg = 'Unauthorized', code = 'UNAUTHORIZED') {
    return new ApiError(401, code, msg);
  }
  static forbidden(msg = 'Forbidden', code = 'FORBIDDEN') {
    return new ApiError(403, code, msg);
  }
  static notFound(msg = 'Not found', code = 'NOT_FOUND') {
    return new ApiError(404, code, msg);
  }
  static conflict(msg = 'Conflict', code = 'CONFLICT', details) {
    return new ApiError(409, code, msg, details);
  }
  static tooMany(msg = 'Too many requests', code = 'RATE_LIMITED') {
    return new ApiError(429, code, msg);
  }
  static internal(msg = 'Internal server error', code = 'INTERNAL') {
    return new ApiError(500, code, msg);
  }
}

module.exports = ApiError;
