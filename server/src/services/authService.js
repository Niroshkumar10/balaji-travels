'use strict';

const db = require('../infra/db');
const env = require('../config/env');
const logger = require('../infra/logger');
const ApiError = require('../utils/apiError');
const otpUtil = require('../utils/otp');
const jwtUtil = require('../utils/jwt');
const { parseUtc } = require('../utils/time');
const smsService = require('./smsService');
const userRepo = require('../repositories/userRepo');
const customerRepo = require('../repositories/customerRepo');
const driverRepo = require('../repositories/driverRepo');
const otpRepo = require('../repositories/otpRepo');

const MAX_OTP_ATTEMPTS = 5;
const LOGIN_ROLES = ['customer', 'driver'];

function ttlToDate(ttl) {
  // ttl like "30d" / "24h" / "3600s" / plain seconds
  const m = /^(\d+)([smhd])?$/.exec(String(ttl).trim());
  if (!m) return new Date(Date.now() + 30 * 864e5);
  const n = Number(m[1]);
  const unit = { s: 1e3, m: 6e4, h: 36e5, d: 864e5 }[m[2] || 's'];
  return new Date(Date.now() + n * unit);
}

const fmt = (d) => new Date(d).toISOString().slice(0, 19).replace('T', ' ');

const authService = {
  /**
   * Generate + store + send an OTP. Any earlier unconsumed OTP for the same
   * (mobile, role) is invalidated so only the newest code works.
   */
  async requestOtp({ mobile, role }) {
    if (!LOGIN_ROLES.includes(role)) {
      throw ApiError.badRequest('role must be customer or driver', 'BAD_ROLE');
    }

    const code = otpUtil.generateCode();
    const codeHash = otpUtil.hashCode(code, mobile, role);
    const expiresAt = new Date(Date.now() + env.OTP_TTL_SECONDS * 1000);

    await db.withTransaction(async (tx) => {
      await otpRepo.invalidateActive(mobile, role, tx);
      await otpRepo.create({ mobile, role, codeHash, expiresAt }, tx);
    });

    const delivery = await smsService.sendOtp(mobile, code);
    logger.info({ mobile, role, ttl: env.OTP_TTL_SECONDS, provider: delivery.provider }, 'otp issued');

    // In non-production the code is returned so the mobile apps / tests can
    // proceed without a real SMS gateway. NEVER in production.
    return {
      sent: true,
      expiresInSeconds: env.OTP_TTL_SECONDS,
      ...(env.isProd ? {} : { devCode: code }),
    };
  },

  /**
   * Verify an OTP and issue a session. Concurrent verifies for the same
   * (mobile, role) are serialised by SELECT ... FOR UPDATE (mysql), so a
   * retried tap or two devices can never both win.
   */
  async verifyOtp({ mobile, role, code }) {
    if (!LOGIN_ROLES.includes(role)) {
      throw ApiError.badRequest('role must be customer or driver', 'BAD_ROLE');
    }

    const bypass =
      !!env.OTP_DEV_BYPASS_CODE && code === env.OTP_DEV_BYPASS_CODE && !env.isProd;

    const session = await db.withTransaction(async (tx) => {
      if (!bypass) {
        const row = await otpRepo.findLatestActive(mobile, role, tx);

        if (!row) throw ApiError.badRequest('No active code — request a new one', 'OTP_NOT_FOUND');
        if (parseUtc(row.expires_at).getTime() < Date.now()) {
          throw ApiError.badRequest('Code expired — request a new one', 'OTP_EXPIRED');
        }
        if (row.attempts >= MAX_OTP_ATTEMPTS) {
          throw ApiError.tooMany('Too many attempts — request a new code', 'OTP_LOCKED');
        }

        const expectedHash = otpUtil.hashCode(code, mobile, role);
        if (!otpUtil.timingSafeEqualHex(row.code_hash, expectedHash)) {
          await otpRepo.incrementAttempts(row.id, tx);
          throw ApiError.badRequest('Incorrect code', 'OTP_INVALID');
        }

        const consumed = await otpRepo.consume(row.id, tx);
        if (consumed === 0) throw ApiError.conflict('Code already used', 'OTP_CONSUMED');
      }

      // ── find-or-create the identity + its role profile ──
      let user = await userRepo.findByMobileAndRole(mobile, role, tx);
      let isNew = false;
      if (!user) {
        const userId = await userRepo.create({ mobile, role }, tx);
        user = { id: userId, mobile, role, name: null, email: null, status: 'active' };
        isNew = true;
      }
      if (user.status !== 'active') {
        throw ApiError.forbidden('This account is blocked. Contact support.', 'ACCOUNT_BLOCKED');
      }

      let profile;
      let profileId;
      if (role === 'customer') {
        profile = await customerRepo.findByUserId(user.id, tx);
        if (!profile) {
          profileId = await customerRepo.create(user.id, tx);
          profile = await customerRepo.findByUserId(user.id, tx);
        } else {
          profileId = profile.id;
        }
      } else {
        profile = await driverRepo.findByUserId(user.id, tx);
        if (!profile) {
          profileId = await driverRepo.create(user.id, tx);
          profile = await driverRepo.findByUserId(user.id, tx);
        } else {
          profileId = profile.id;
        }
      }

      const token = jwtUtil.signAccess({ userId: user.id, role, profileId });
      const expiry = ttlToDate(env.JWT_ACCESS_TTL);
      await userRepo.setSession(user.id, token, fmt(expiry), tx);

      return { token, user, profile, isNew };
    });

    logger.info(
      { mobile, role, userId: session.user.id, isNew: session.isNew },
      'login ok',
    );

    return {
      token: session.token,
      isNewUser: session.isNew,
      user: {
        id: session.user.id,
        mobile: session.user.mobile,
        role,
        name: session.user.name,
        email: session.user.email,
      },
      profile: session.profile,
    };
  },

  async logout(userId, role) {
    await userRepo.clearSession(userId);
    if (role === 'driver') {
      const d = await driverRepo.findByUserId(userId);
      if (d) {
        await driverRepo
          .setPresence(d.id, { isOnline: false, availability: 'offline' })
          .catch((err) =>
            logger.warn({ err: err.message }, 'driver presence clear on logout failed'),
          );
      }
    }
    return { ok: true };
  },

  async registerFcmToken(userId, fcmToken) {
    await userRepo.setFcmToken(userId, fcmToken);
    return { ok: true };
  },
};

module.exports = authService;
