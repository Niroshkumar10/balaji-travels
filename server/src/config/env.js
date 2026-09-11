'use strict';

/**
 * Boot-time environment validation.
 *
 * Every value the app depends on is declared here with a type and (where it
 * matters) a constraint. `env` is frozen and imported everywhere instead of
 * reading `process.env` directly, so a missing/misspelt/blank variable fails
 * loudly at startup with an exact message, never silently at 2am in a handler.
 */

const path = require('path');
const dotenv = require('dotenv');
const { z } = require('zod');

// Load .env from the server/ root (one level up from src/). Real environment
// variables already set (CI, container) win over the file.
dotenv.config({ path: path.join(__dirname, '..', '..', '.env') });

const bool = (def = false) =>
  z
    .enum(['true', 'false', '1', '0', ''])
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : v === 'true' || v === '1'));

const int = (def) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : Number(v)))
    .pipe(z.number().int());

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: int(30009),
    API_BASE_URL: z.string().url().default('https://chat.neuralarc.com'),

    // 'mysql' — real MySQL/MariaDB pool (production + normal dev).
    // 'memory' — in-process store, NO database. Dev/demo/tests only: lets the
    //            OTP + profile flow run with zero external services. Never in prod.
    DB_DRIVER: z.enum(['mysql', 'memory']).default('mysql'),
    DB_HOST: z.string().optional().default(''),
    DB_PORT: int(3306),
    DB_USER: z.string().optional().default(''),
    DB_PASSWORD: z.string().default(''),
    DB_NAME: z.string().optional().default(''),
    DB_POOL_SIZE: int(20).pipe(z.number().int().min(2).max(200)),

    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    JWT_ACCESS_TTL: z.string().default('30d'),
    // Socket handshake: when true, a live socket is refused / dropped the moment
    // its account logs in again anywhere (the REST layer always does this).
    // Default false — a validly-signed, unexpired JWT is enough to hold the
    // socket open, so re-logins on the same phone don't kill the connection.
    SOCKET_STRICT_SESSION: bool(false),
    OTP_TTL_SECONDS: int(300),
    OTP_LENGTH: int(6).pipe(z.number().int().min(4).max(8)),
    // Min seconds between OTP requests for the same (mobile, role) — the
    // "resend cooldown". The apps also show a countdown, this enforces it.
    OTP_RESEND_COOLDOWN_SECONDS: int(30),
    // TESTING ONLY: when true, the OTP is returned in the /auth/otp/request
    // response (and logged) even in production — for use before a real SMS
    // gateway is wired. Turn OFF the moment SMS works.
    OTP_EXPOSE_CODE: bool(false),
    OTP_DEV_BYPASS_CODE: z.string().optional().transform((v) => (v && v.trim() ? v.trim() : null)),

    ADMIN_HMAC_SECRET: z.string().min(16),

    SMS_PROVIDER: z.enum(['console', 'ping4sms', 'msg91', 'twilio']).default('console'),
    SMS_API_KEY: z.string().optional().default(''),
    SMS_SENDER_ID: z.string().optional().default(''),
    SMS_TEMPLATE_ID: z.string().optional().default(''),

    FIREBASE_SERVICE_ACCOUNT_PATH: z
      .string()
      .optional()
      .transform((v) => (v && v.trim() ? v.trim() : null)),

    GOOGLE_MAPS_SERVER_KEY: z.string().optional().default(''),

    RAZORPAY_KEY_ID: z.string().optional().default(''),
    RAZORPAY_KEY_SECRET: z.string().optional().default(''),
    RAZORPAY_WEBHOOK_SECRET: z.string().optional().default(''),

    DISPATCH_SEARCH_RADIUS_KM: int(5),
    // Radius for the queue-exhaustion re-query. 0 = no distance limit
    // (offer to ANY online driver of the right category, nearest first).
    DISPATCH_EXPAND_RADIUS_KM: int(0),
    DISPATCH_OFFER_TIMEOUT_MS: int(25000),
    DISPATCH_MAX_DRIVERS: int(8),
    DISPATCH_NO_DRIVER_TIMEOUT_MS: int(120000),
    DRIVER_OFFLINE_SWEEP_SECONDS: int(120),
    // A driver's last GPS ping older than this is treated as "not there" by
    // dispatch. Must be comfortably larger than the app's heartbeat interval.
    DRIVER_LOCATION_STALE_SECONDS: int(120),

    // Platform commission on each completed ride's fare (percent).
    COMMISSION_PCT: int(20).pipe(z.number().int().min(0).max(90)),
    // Throttle for persisting the driver breadcrumb trail during a ride.
    TRACK_LOG_MIN_INTERVAL_MS: int(5000),
    TRACK_LOG_MIN_MOVE_M: int(40),
  })
  .superRefine((val, ctx) => {
    if (val.NODE_ENV === 'production' && val.OTP_DEV_BYPASS_CODE) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['OTP_DEV_BYPASS_CODE'],
        message: 'OTP_DEV_BYPASS_CODE must not be set in production',
      });
    }
    if (val.NODE_ENV === 'production' && val.DB_DRIVER === 'memory') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['DB_DRIVER'],
        message: 'DB_DRIVER=memory is not allowed in production',
      });
    }
    if (val.DB_DRIVER === 'mysql') {
      for (const key of ['DB_HOST', 'DB_USER', 'DB_NAME']) {
        if (!val[key]) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: [key],
            message: `${key} is required when DB_DRIVER=mysql`,
          });
        }
      }
    }
  });

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  const lines = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`);
  // eslint-disable-next-line no-console
  console.error(`\n✗ Invalid environment configuration:\n${lines.join('\n')}\n`);
  process.exit(1);
}

const env = Object.freeze({
  ...parsed.data,
  isProd: parsed.data.NODE_ENV === 'production',
  isTest: parsed.data.NODE_ENV === 'test',
  isDev: parsed.data.NODE_ENV === 'development',
});

module.exports = env;
