'use strict';

/**
 * OTP SMS delivery, behind a thin provider interface.
 *
 * The only method the rest of the app calls is `sendOtp(mobile, code)`. Swap
 * SMS_PROVIDER in .env to change gateways without touching callers. The default
 * `console` provider just logs — good for local dev and automated tests, and
 * it never makes a network call.
 */

const env = require('../config/env');
const logger = require('../infra/logger');

async function consoleProvider(mobile, code) {
  logger.info({ mobile, code }, '[sms:console] OTP (dev only — not actually sent)');
  return { provider: 'console', ok: true };
}

async function ping4smsProvider(mobile, code) {
  // Placeholder — wire the real ping4sms HTTP call when credentials are provisioned.
  const params = new URLSearchParams({
    key: env.SMS_API_KEY,
    route: '2',
    sender: env.SMS_SENDER_ID,
    number: `91${mobile}`,
    sms: `${code} is your RedTaxi verification code. Do not share it.`,
    templateid: env.SMS_TEMPLATE_ID,
  });
  const res = await fetch(`https://site.ping4sms.com/api/smsapi?${params.toString()}`);
  const body = await res.text();
  const ok = /^\d+$/.test(body.trim());
  if (!ok) logger.warn({ body }, '[sms:ping4sms] gateway did not return a message id');
  return { provider: 'ping4sms', ok, raw: body };
}

const providers = {
  console: consoleProvider,
  ping4sms: ping4smsProvider,
  // msg91 / twilio: add when needed
};

async function sendOtp(mobile, code) {
  const provider = providers[env.SMS_PROVIDER] ?? consoleProvider;
  try {
    return await provider(mobile, code);
  } catch (err) {
    // OTP SMS failure is non-fatal to the request — the code is already stored;
    // the user can request a resend. Log and move on.
    logger.error({ err: err.message, provider: env.SMS_PROVIDER, mobile }, 'sms send failed');
    return { provider: env.SMS_PROVIDER, ok: false, error: err.message };
  }
}

module.exports = { sendOtp };
