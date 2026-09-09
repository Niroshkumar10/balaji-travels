import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import 'earnings_controller.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  Future<void> _requestPayout(BuildContext context, WidgetRef ref, double balance) async {
    final ctrl = TextEditingController(text: balance.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request payout'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: '₹ ',
            helperText: 'Available: ${money(balance)}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Request')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ctrl.text.trim()) ?? 0;
    final res = await ref.read(miscRepoProvider).requestPayout(amount);
    if (!context.mounted) return;
    res.when(
      ok: (_) {
        ref.invalidate(payoutsProvider);
        ref.invalidate(todayEarningsProvider);
        ref.invalidate(earningsSummaryProvider);
        showOk(context, 'Payout requested');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todayEarningsProvider);
    final payouts = ref.watch(payoutsProvider);

    return Scaffold(
      appBar: const RtAppBar(title: 'Wallet & payouts', fallbackRoute: '/d/dashboard'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          summary.when(
            loading: () => const Card(
              child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            ),
            error: (e, _) => Text('$e'),
            data: (s) => Card(
              color: AppColors.brand,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Wallet balance', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(money(s.walletBalance),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.ink,
                      ),
                      onPressed: s.walletBalance <= 0
                          ? null
                          : () => _requestPayout(context, ref, s.walletBalance),
                      child: const Text('Request payout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Payout history', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          payouts.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(icon: Icons.savings_rounded, title: 'No payouts yet');
              }
              return Column(
                children: rows
                    .map((p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_balance_rounded),
                          title: Text(money(p.amount)),
                          subtitle: Text(dateTimeLabel(p.requestedAt)),
                          trailing: StatusPill(
                            p.status,
                            color: switch (p.status) {
                              'paid' => AppColors.success,
                              'failed' => AppColors.danger,
                              _ => AppColors.info,
                            },
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
