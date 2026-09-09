'use strict';

const env = require('../config/env');
const db = require('../infra/db');
const ApiError = require('../utils/apiError');
const walletRepo = require('../repositories/walletRepo');

const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

const PERIOD_SQL = {
  day: 'CURDATE()',
  week: 'DATE_SUB(CURDATE(), INTERVAL 7 DAY)',
  month: 'DATE_SUB(CURDATE(), INTERVAL 30 DAY)',
  all: null,
};

const earningsService = {
  /**
   * Credit a completed ride's fare to the driver, net of platform commission.
   * Idempotent-by-construction: called exactly once, from the payment-settled
   * path, inside that transaction (pass its ctx).
   */
  async creditRide(ctx, driverId, ride) {
    const fare = Number(ride.final_fare ?? ride.est_fare ?? 0);
    if (fare <= 0) return;
    const commission = round2((fare * env.COMMISSION_PCT) / 100);

    await walletRepo.apply(ctx, driverId, {
      rideId: ride.id,
      type: 'trip_earning',
      amount: fare,
      ref: ride.ride_ref,
      note: 'Trip fare',
    });
    if (commission > 0) {
      await walletRepo.apply(ctx, driverId, {
        rideId: ride.id,
        type: 'commission',
        amount: -commission,
        ref: ride.ride_ref,
        note: `Platform commission ${env.COMMISSION_PCT}%`,
      });
    }
  },

  async summary(driverId, period = 'day') {
    const key = PERIOD_SQL[period] === undefined ? 'day' : period;
    const s = await walletRepo.summary(driverId, PERIOD_SQL[key] ?? null);
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
