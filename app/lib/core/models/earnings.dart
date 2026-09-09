import 'json.dart';

class EarningsSummary {
  const EarningsSummary({
    required this.period,
    required this.trips,
    required this.gross,
    required this.commission,
    required this.incentives,
    required this.net,
    required this.paidOut,
    required this.walletBalance,
  });

  final String period;
  final int trips;
  final double gross;
  final double commission;
  final double incentives;
  final double net;
  final double paidOut;
  final double walletBalance;

  factory EarningsSummary.fromJson(Map<String, dynamic> j) => EarningsSummary(
        period: j['period']?.toString() ?? 'day',
        trips: asInt(j['trips']),
        gross: asDouble(j['gross']),
        commission: asDouble(j['commission']),
        incentives: asDouble(j['incentives']),
        net: asDouble(j['net']),
        paidOut: asDouble(j['paidOut']),
        walletBalance: asDouble(j['walletBalance']),
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.rideId,
    this.note,
    this.createdAt,
  });

  final int id;
  final String type; // trip_earning | commission | incentive | payout | adjustment
  final double amount;
  final double balanceAfter;
  final int? rideId;
  final String? note;
  final DateTime? createdAt;

  bool get isCredit => amount >= 0;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: asInt(j['id']),
        type: j['type']?.toString() ?? '',
        amount: asDouble(j['amount']),
        balanceAfter: asDouble(j['balance_after']),
        rideId: asIntOrNull(j['ride_id']),
        note: j['note']?.toString(),
        createdAt: asDate(j['created_at']),
      );
}

class Payout {
  const Payout({
    required this.id,
    required this.amount,
    required this.status,
    this.requestedAt,
    this.processedAt,
  });

  final int id;
  final double amount;
  final String status;
  final DateTime? requestedAt;
  final DateTime? processedAt;

  factory Payout.fromJson(Map<String, dynamic> j) => Payout(
        id: asInt(j['id']),
        amount: asDouble(j['amount']),
        status: j['status']?.toString() ?? 'requested',
        requestedAt: asDate(j['requested_at']),
        processedAt: asDate(j['processed_at']),
      );
}
