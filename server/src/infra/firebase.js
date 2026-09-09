'use strict';

/**
 * Firebase Cloud Messaging (push).
 *
 * Initialised from a service-account JSON whose path is given by
 * FIREBASE_SERVICE_ACCOUNT_PATH — the file lives OUTSIDE the repo and is never
 * committed. If the path is unset or the file can't be read, push is silently
 * disabled so local dev and CI don't need Firebase credentials. `messaging`
 * is null in that case and `sendPush()` is a no-op that returns false.
 */

const fs = require('fs');
const admin = require('firebase-admin');
const env = require('../config/env');
const logger = require('./logger');

let messaging = null;

if (env.FIREBASE_SERVICE_ACCOUNT_PATH) {
  try {
    const raw = fs.readFileSync(env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8');
    const serviceAccount = JSON.parse(raw);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    messaging = admin.messaging();
    logger.info('firebase messaging initialised');
  } catch (err) {
    logger.error({ err }, 'firebase init failed — push disabled');
  }
} else {
  logger.warn('FIREBASE_SERVICE_ACCOUNT_PATH not set — push disabled');
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
