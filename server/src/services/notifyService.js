'use strict';

/**
 * One call → three sinks, in priority order of authority:
 *   1. rt_notifications  (the durable record — the app reads this on open)
 *   2. Socket.IO         (instant, if the user has a live socket)
 *   3. FCM push          (best-effort wake-up when the app is backgrounded/killed)
 *
 * Notifications are never the source of truth — the DB + REST are. A dropped
 * push or socket just means the user sees it on next refresh.
 */

const logger = require('../infra/logger');
const L = logger.for('notify'); // → logs/notify.log
const notificationRepo = require('../repositories/notificationRepo');
const userRepo = require('../repositories/userRepo');
const firebase = require('../infra/firebase');
const realtime = require('../realtime/emitter');

async function notify(userId, { type, title, body, data = {}, socketEvent = 'notification' }) {
  try {
    const id = await notificationRepo.create({ userId, type, title, body, data });

    const delivery = realtime.toUserVerbose(userId, socketEvent, { id, type, title, body, data, ts: Date.now() });

    const user = await userRepo.findById(userId);
    let push = 'skipped_no_token';
    if (!firebase.isEnabled) {
      push = 'skipped_firebase_disabled';
    } else if (user?.fcm_token) {
      const sent = await firebase.sendPush(user.fcm_token, { type, title, body: body ?? '', ...data });
      push = sent ? 'sent' : 'failed';
    }

    L.event(push === 'sent' ? '🔔' : '🔕', 'notify', {
      id,
      userId,
      type,
      title,
      socketDelivered: delivery.delivered,
      push,
    });
    return id;
  } catch (err) {
    L.warnEvent('⚠️', 'notify failed', { err: err.message, userId, type, title });
    return null;
  }
}

module.exports = { notify };
