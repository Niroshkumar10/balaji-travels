'use strict';

/**
 * Firebase Cloud Messaging (push).
 *
 * Credentials come from a service-account JSON. Resolution order:
 *   1. FIREBASE_SERVICE_ACCOUNT_PATH  (explicit path, any deploy layout)
 *   2. server/firebase-service-account.json  (drop-in convention, like Microlab)
 *
 * The file is git-ignored and never committed. If neither is present, push is
 * disabled: `messaging` is null and `sendPush()` is a no-op returning false, so
 * dev / CI need no Firebase credentials.
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const env = require('../config/env');
const logger = require('./logger');

const DEFAULT_PATH = path.join(__dirname, '..', '..', 'firebase-service-account.json');
const accountPath = env.FIREBASE_SERVICE_ACCOUNT_PATH || DEFAULT_PATH;

let messaging = null;

if (fs.existsSync(accountPath)) {
  try {
    const serviceAccount = JSON.parse(fs.readFileSync(accountPath, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    messaging = admin.messaging();
    logger.info({ accountPath }, 'firebase messaging initialised');
  } catch (err) {
    logger.error({ err, accountPath }, 'firebase init failed — push disabled');
  }
} else {
  logger.info(
    { tried: accountPath },
    'no firebase service account — push disabled (drop firebase-service-account.json in server/ to enable)',
  );
}

/**
 * Send a data-only push to one device token. Data-only (no `notification`
 * block) so the client's background handler always runs and can render a
 * custom notification with action buttons (ride offers need Accept/Decline).
 *
 * @param {string|null} token
 * @param {Record<string,string>} data  — string values only (FCM requirement)
 * @returns {Promise<boolean>} delivered?
 */
async function sendPush(token, data) {
  if (!messaging || !token) return false;
  const stringData = Object.fromEntries(
    Object.entries(data ?? {}).map(([k, v]) => [k, v == null ? '' : String(v)]),
  );
  try {
    await messaging.send({
      token,
      data: stringData,
      android: { priority: 'high' },
      apns: { headers: { 'apns-priority': '10' }, payload: { aps: { contentAvailable: true } } },
    });
    return true;
  } catch (err) {
    logger.warn({ err: err.message, code: err.code }, 'push send failed');
    return false;
  }
}

module.exports = { admin, messaging, sendPush, isEnabled: Boolean(messaging) };
