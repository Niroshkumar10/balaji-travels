'use strict';

const ApiError = require('../utils/apiError');

/**
 * Restrict a route to one or more roles. The role comes from the verified
 * token (req.auth.role), never from the request body — the client cannot
 * claim to be a driver or admin.
 *
 *   router.get('/earnings', authenticate, requireRole('driver'), handler)
 */
function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.auth) return next(ApiError.unauthorized());
    if (!roles.includes(req.auth.role)) {
      return next(ApiError.forbidden(`Requires role: ${roles.join(' or ')}`, 'WRONG_ROLE'));
    }
    next();
  };
}

module.exports = requireRole;
