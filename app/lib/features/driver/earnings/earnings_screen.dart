import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import 'earnings_controller.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key, this.showBack = true});
  final bool showBack;
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
      appBar: RtAppBar(
        title: 'Earnings',
        fallbackRoute: '/d/dashboard',
        showBack: widget.showBack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          async.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (s) => Text(money(s.net), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const Text('Net earnings', style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 20),
          ledger.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) => _WeekChart(rows: rows),
          ),
          const SizedBox(height: 20),
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
            data: (s) => Column(
              children: [
                Row(
                  children: [
                    _StatCard(label: 'Trips completed', value: '${s.trips}'),
                    const SizedBox(width: 10),
                    _StatCard(label: 'Gross fares', value: money(s.gross)),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        InfoRow('Gross fares', money(s.gross)),
                        InfoRow('Platform commission', '- ${money(s.commission)}'),
                        if (s.incentives > 0) InfoRow('Incentives', money(s.incentives)),
                        const Divider(),
                        InfoRow('Net earnings', money(s.net), strong: true),
                        InfoRow('Wallet balance', money(s.walletBalance)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/d/wallet'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.savings_rounded, size: 18),
            label: const Text('Wallet & withdraw'),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Recent activity'),
          ledger.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(icon: Icons.receipt_long_rounded, title: 'No activity yet');
              }
              return Column(
                children: rows
                    .map((e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: (e.isCredit ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
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
                            style: TextStyle(fontWeight: FontWeight.w700, color: e.isCredit ? AppColors.success : AppColors.danger),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

/// A plain, dependency-free bar chart of the last 7 days' credited earnings
/// — built directly from the real ledger (no charting package, no mock
/// numbers). Days with nothing earned just show a hairline bar.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.rows});
  final List<LedgerEntry> rows;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i)));
    final totals = days.map((d) {
      return rows.where((r) => r.isCredit && r.createdAt != null && _sameDay(r.createdAt!, d)).fold<double>(0, (a, r) => a + r.amount);
    }).toList();
    final maxV = totals.fold<double>(1, (a, v) => v > a ? v : a);

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final h = 8 + (totals[i] / maxV) * 84;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: i == 6 ? AppColors.primary : AppColors.secondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_weekdayLabel(days[i]), style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _weekdayLabel(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}
