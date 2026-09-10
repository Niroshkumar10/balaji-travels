'use strict';

/**
 * Structured logger (pino) rendered as readable text, split per feature.
 *
 * Console  — one readable line (or a boxed block) per event.
 * Files (server/logs/):
 *   app.log        — everything
 *   error.log      — warn + error only
 *   <feature>.log  — only events tagged with that feature (dispatch.log,
 *                    presence.log, …)
 *
 * In a module, use `logger.for('dispatch')` instead of `logger`:
 *   const L = require('../infra/logger').for('dispatch');
 *   L.event('📤', 'offer sent', { rideId, driverId });
 *   L.block('🔍', `Ride #${id} — driver search`, [ 'line 1', 'line 2' ]);
 *
 * `redact` strips tokens / OTPs / passwords / secrets at every nesting level.
 */

const fs = require('fs');
const path = require('path');
const { Writable } = require('stream');
const pino = require('pino');
const env = require('../config/env');

const redactPaths = [
  'req.headers.authorization',
  'req.headers.cookie',
  '*.token',
  '*.accessToken',
  '*.auth_token',
  '*.password',
  '*.otp',
  '*.code',
  '*.code_hash',
  '*.jwt',
  '*.secret',
  '*.key_secret',
  '*.RAZORPAY_KEY_SECRET',
  'headers.authorization',
];

const LOG_DIR = path.join(__dirname, '..', '..', 'logs'); // server/logs
const level = env.isTest ? 'silent' : env.isProd ? 'info' : 'debug';

const LEVEL_NAME = { 10: 'TRACE', 20: 'DEBUG', 30: 'INFO', 40: 'WARN', 50: 'ERROR', 60: 'FATAL' };
const HIDE = new Set(['level', 'time', 'msg', 'service', 'mod', 'pid', 'hostname', 'v', 'emoji', 'lines']);

// ISO-style local time (Asia/Kolkata), e.g. "2026-09-10 13:15:28 IST"
const stamp = (t) =>
  `${new Date(t)
    .toLocaleString('sv-SE', { timeZone: 'Asia/Kolkata', hour12: false })
    .replace(',', '')} IST`;

function scalar(v) {
  if (v === null || v === undefined) return String(v);
  return typeof v === 'object' ? JSON.stringify(v) : String(v);
}

function pair(k, v) {
  if (k === 'req' && v && typeof v === 'object') return `req="${v.method} ${v.url}"`;
  if (k === 'res' && v && typeof v === 'object') return `res=${v.statusCode}`;
  return `${k}=${scalar(v)}`;
}

/** One pino JSON record → readable text (a line, or a boxed block). */
function render(rec) {
  const ts = stamp(rec.time || Date.now());
  const tag = rec.mod ? ` [${rec.mod}]` : '';
  const emoji = rec.emoji ? `${rec.emoji}  ` : '';

  if (Array.isArray(rec.lines)) {
    const bar = '─'.repeat(66);
    const body = rec.lines.map((l) => (l ? `   ${l}` : '')).join('\n');
    return `\n${bar}\n${ts}${tag}  ${emoji}${(rec.msg || '').trim()}\n${bar}\n${body}\n${bar}\n`;
  }

  const lvl = (LEVEL_NAME[rec.level] || String(rec.level || '')).padEnd(5);
  const extras = Object.entries(rec)
    .filter(([k]) => !HIDE.has(k))
    .map(([k, v]) => pair(k, v))
    .join('  ');
  return `${ts}  ${lvl}${tag}  ${emoji}${rec.msg || ''}${extras ? `  ·  ${extras}` : ''}\n`;
}

/** Buffers partial writes, hands each complete JSON line to `onRecord`. */
function lineSink(onRecord) {
  let buf = '';
  return new Writable({
    write(chunk, _enc, cb) {
      buf += chunk.toString();
      let nl;
      while ((nl = buf.indexOf('\n')) !== -1) {
        const raw = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!raw.trim()) continue;
        let rec = null;
        try {
          rec = JSON.parse(raw);
        } catch {
          /* leave rec null — onRecord falls back to raw */
        }
        try {
          onRecord(rec, raw);
        } catch {
          /* never let logging crash the app */
        }
      }
      cb();
    },
  });
}

function destination() {
  if (env.isTest) return process.stdout;

  fs.mkdirSync(LOG_DIR, { recursive: true });
  const append = (name, text) => {
    try {
      fs.appendFileSync(path.join(LOG_DIR, name), text);
    } catch {
      /* ignore */
    }
  };

  const consoleSink = lineSink((rec, raw) =>
    process.stdout.write(rec ? render(rec) : `${raw}\n`),
  );

  const fileSink = lineSink((rec, raw) => {
    const text = rec ? render(rec) : `${raw}\n`;
    append('app.log', text);
    if (rec && typeof rec.mod === 'string') append(`${rec.mod}.log`, text);
    if (rec && rec.level >= 40) append('error.log', text);
  });

  return pino.multistream([
    { level, stream: consoleSink },
    { level, stream: fileSink },
  ]);
}

const logger = pino(
  {
    level,
    redact: { paths: redactPaths, censor: '[redacted]' },
    base: { service: 'redtaxi-server' },
    timestamp: pino.stdTimeFunctions.isoTime,
  },
  destination(),
);

/**
 * A feature-scoped logger. Its lines also land in `logs/<feature>.log`.
 *   .event(emoji, msg, fields?)  — one readable line
 *   .block(emoji, title, lines)  — a boxed multi-line block
 */
logger.for = (feature) => {
  const child = logger.child({ mod: feature });
  child.event = (emoji, msg, fields = {}) => child.info({ emoji, ...fields }, msg);
  child.warnEvent = (emoji, msg, fields = {}) => child.warn({ emoji, ...fields }, msg);
  child.block = (emoji, title, lines = []) => child.info({ emoji, lines }, title);
  return child;
};

module.exports = logger;
