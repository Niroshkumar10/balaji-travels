'use strict';

// Tests run against the in-memory driver — no MySQL / Redis / SMS / Firebase.
process.env.NODE_ENV = 'test';
process.env.DB_DRIVER = 'memory';
process.env.REDIS_URL = '';
process.env.SMS_PROVIDER = 'console';
process.env.FIREBASE_SERVICE_ACCOUNT_PATH = '';
process.env.JWT_SECRET = 'test-secret-key-at-least-32-characters-long-xxxx';
process.env.ADMIN_HMAC_SECRET = 'test-admin-hmac-secret';
process.env.OTP_TTL_SECONDS = '300';
