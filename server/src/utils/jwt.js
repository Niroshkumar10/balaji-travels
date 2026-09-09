'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const env = require('../config/env');

/**
 * Access-token claims:
 *   sub  — rt_users.id
 *   role — 'customer' | 'driver' | 'admin'
 *   pid  — profile id (rt_customers.id or rt_drivers.id); null for admin
 *   jti  — random per-issue nonce, so two logins in the same second still
 *          produce distinct tokens (otherwise identical iat/payload ⇒ identical
 *          signature ⇒ the "new" login wouldn't visibly supersede the old one).
 *
 * The token is only half the auth story — middleware/auth.js also checks that
 * this exact string is still the one stored on rt_users.auth_token, so logout
 * (or a newer login on another device) revokes it immediately.
 */
function signAccess({ userId, role, profileId }) {
  return jwt.sign(
    {
      sub: String(userId),
      role,
      pid: profileId != null ? String(profileId) : null,
      jti: crypto.randomUUID(),
    },
    env.JWT_SECRET,
    { expiresIn: env.JWT_ACCESS_TTL },
  );
}

function verify(token) {
  return jwt.verify(token, env.JWT_SECRET);
}

module.exports = { signAccess, verify };
