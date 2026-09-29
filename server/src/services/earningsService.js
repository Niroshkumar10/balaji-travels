'use strict';

const env = require('../config/env');
const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const walletRepo = require('../repositories/walletRepo');
const { parseDbTimestampUtc } = require('../utils/rideWindow');

const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

// The DB stores every timestamp as a real UTC instant (see infra/db.js's
// session time_zone fix), but "today"/"this week" for a driver means the
// IST calendar day, not the UTC one — they disagree by up to ~5.5h near
// midnight IST (e.g. 2 AM IST is still "yesterday" in UTC). This computes
// the UTC instant that corresponds to IST midnight, `daysAgo` days back, so
// period boundaries are always evaluated against the driver's actual local
// calendar day, not the server's.
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
function istDayBoundary(daysAgo) {
  const shifted = new Date(Date.now() + IST_OFFSET_MS);
  // shifted's UTC-labelled y/m/d fields now read as IST wall-clock date —
  // Date.UTC(...) on them gives "IST midnight" mislabelled as UTC; shifting
  // back by the same offset converts that back to the true UTC instant.
  const istMidnightMislabelledUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate() - daysAgo,
  );
  return new Date(istMidnightMislabelledUtc - IST_OFFSET_MS);
}

// Real bound values now (a Date, mysql2 serialises it correctly per the
// pool's timezone:'Z' option — same mechanism already proven correct for
// scheduled_at) — NOT raw SQL fragments. walletRepo.summary() binds this as
// a normal parameter, so it must never be a SQL expression string again:
// that was the actual bug (see the fix's commit message / earningsService
// history) — `:since` bound to the literal string 'CURDATE()' made every
// period filter silently match everything, showing all-time totals as
// "today".
const PERIOD_SINCE = {
  day: () => istDayBoundary(0),
  week: () => istDayBoundary(7),
  month: () => istDayBoundary(30),
  all: () => null,
};

const earningsService = {
  /**
   * Credit a completed ride's fare to the driver, net of platform commission.
   * Idempotent-by-construction: called exactly once, from the payment-settled
   * path, inside that transaction (pass its ctx).
   *
   * The ledger entry is dated by the RIDE's own completion time, not "now" —
   * for a live settlement these are the same instant anyway (completed_at
   * was just set by this same transaction), but for
   * paymentService.backfillExternalCompletion() (a ride completed hours or
   * days ago, only just discovered) this is what stops a maintenance run
   * from making an old trip's earnings show up under "Today".
   */
  async creditRide(ctx, driverId, ride) {
    const fare = Number(ride.final_fare ?? ride.est_fare ?? 0);
    if (fare <= 0) return;
    const commission = round2((fare * env.COMMISSION_PCT) / 100);
    const occurredAt = ride.completed_at ? parseDbTimestampUtc(ride.completed_at) : null;

    await walletRepo.apply(ctx, driverId, {
      rideId: ride.id,
      type: 'trip_earning',
      amount: fare,
      ref: ride.ride_ref,
      note: 'Trip fare',
      occurredAt,
    });
    if (commission > 0) {
      await walletRepo.apply(ctx, driverId, {
        rideId: ride.id,
        type: 'commission',
        amount: -commission,
        ref: ride.ride_ref,
        note: `Platform commission ${env.COMMISSION_PCT}%`,
        occurredAt,
      });
    }
  },

  async summary(driverId, period = 'day') {
    const key = PERIOD_SINCE[period] ? period : 'day';
    const s = await walletRepo.summary(driverId, PERIOD_SINCE[key]());
    const balance = await walletRepo.getBalance(driverId);
    return {
      period: key,
      trips: Number(s.trips ?? 0),
      gross: round2(Number(s.gross ?? 0)),
      commission: round2(Math.abs(Number(s.commission ?? 0))),
      incentives: round2(Number(s.incentives ?? 0)),
      net: round2(Number(s.gross ?? 0) + Number(s.commission ?? 0) + Number(s.incentives ?? 0)),
      paidOut: round2(Number(s.paid_out ?? 0)),
      walletBalance: balance,
    };
  },

  ledger(driverId, opts) {
    return walletRepo.ledger(driverId, opts);
  },

  async requestPayout(driverId, amount) {
    const amt = round2(Number(amount));
    if (!(amt > 0)) throw ApiError.badRequest('Amount must be positive', 'BAD_AMOUNT');
    return db.withTransaction(async (tx) => {
      const balance = await walletRepo.getBalance(driverId, tx);
      if (amt > balance) throw ApiError.badRequest('Amount exceeds wallet balance', 'INSUFFICIENT_BALANCE');
      const payoutId = await walletRepo.createPayout(tx, driverId, amt);
      await walletRepo.apply(tx, driverId, {
        type: 'payout',
        amount: -amt,
        ref: `PO-${payoutId}`,
        note: 'Payout requested',
      });
      return { payoutId, amount: amt, status: 'requested' };
    });
  },

  listPayouts(driverId) {
    return walletRepo.listPayouts(driverId);
  },
};

module.exports = earningsService;
