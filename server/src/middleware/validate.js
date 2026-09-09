'use strict';

/**
 * Request validation. `validate({ body, params, query })` where each value is a
 * Zod schema. Parsed (and coerced) results replace req.body / req.params /
 * req.query, so handlers work with clean, typed data and never re-parse.
 */

function validate(schemas) {
  return (req, res, next) => {
    try {
      if (schemas.body) req.body = schemas.body.parse(req.body ?? {});
      if (schemas.params) req.params = schemas.params.parse(req.params ?? {});
      if (schemas.query) req.query = schemas.query.parse(req.query ?? {});
      next();
    } catch (err) {
      next(err); // ZodError — handled centrally in middleware/error.js
    }
  };
}

module.exports = validate;
