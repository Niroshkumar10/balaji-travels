import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import 'earnings_controller.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});
  @override
  ConsumerState<EarningsScreen> createState() => _State();
}

class _State extends ConsumerState<EarningsScreen> {
  String _period = 'day';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(earningsSummaryProvider(_period));
    final ledger = ref.watch(ledgerProvider);

    return Scaffold(
      appBar: const RtAppBar(title: 'Earnings', fallbackRoute: '/d/dashboard'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Today')),
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (s) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(money(s.net), style: Theme.of(context).textTheme.displaySmall),
                    const Text('Net earnings', style: TextStyle(color: AppColors.inkSoft)),
                    const Divider(height: 28),
                    InfoRow('Trips', '${s.trips}'),
                    InfoRow('Gross fares', money(s.gross)),
                    InfoRow('Platform commission', '- ${money(s.commission)}'),
                    if (s.incentives > 0) InfoRow('Incentives', money(s.incentives)),
                    const Divider(),
                    InfoRow('Wallet balance', money(s.walletBalance), strong: true),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ledger.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'No activity yet',
                );
              }
              return Column(
                children: rows
                    .map((e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: (e.isCredit ? AppColors.success : AppColors.danger)
                                .withValues(alpha: 0.12),
                            child: Icon(
                              e.isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: e.isCredit ? AppColors.success : AppColors.danger,
                              size: 18,
                            ),
                          ),
                          title: Text(e.note ?? e.type.replaceAll('_', ' ')),
                          subtitle: Text(dateTimeLabel(e.createdAt)),
                          trailing: Text(
                            '${e.isCredit ? '+' : ''}${money(e.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: e.isCredit ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
