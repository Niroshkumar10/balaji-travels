import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../state/providers.dart';

final todayEarningsProvider = FutureProvider.autoDispose<EarningsSummary>((ref) async {
  final res = await ref.watch(miscRepoProvider).earningsSummary('day');
  return res.valueOrNull ??
      const EarningsSummary(
        period: 'day',
        trips: 0,
        gross: 0,
        commission: 0,
        incentives: 0,
        net: 0,
        paidOut: 0,
        walletBalance: 0,
      );
});

final earningsSummaryProvider =
    FutureProvider.autoDispose.family<EarningsSummary, String>((ref, period) async {
  final res = await ref.watch(miscRepoProvider).earningsSummary(period);
  return res.valueOrNull ??
      EarningsSummary(
        period: period,
        trips: 0,
        gross: 0,
        commission: 0,
        incentives: 0,
        net: 0,
        paidOut: 0,
        walletBalance: 0,
      );
});

final ledgerProvider = FutureProvider.autoDispose<List<LedgerEntry>>((ref) async {
  final res = await ref.watch(miscRepoProvider).earningsLedger(limit: 60);
  return res.valueOrNull ?? const [];
});

final payoutsProvider = FutureProvider.autoDispose<List<Payout>>((ref) async {
  final res = await ref.watch(miscRepoProvider).payouts();
  return res.valueOrNull ?? const [];
});
