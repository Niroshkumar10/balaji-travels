import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _offersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(miscRepoProvider).promos();
  return res.valueOrNull ?? [];
});

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_offersProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Offers', fallbackRoute: '/c/home'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (offers) {
          if (offers.isEmpty) {
            return const EmptyState(
              icon: Icons.local_offer_rounded,
              title: 'No offers right now',
              subtitle: 'Check back soon for ride discounts.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: offers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final o = offers[i];
              final isPercent = o['type'] == 'percent';
              final value = o['value'];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isPercent ? '$value% OFF' : '${money(value)} OFF',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: o['code']?.toString() ?? ''));
                              showOk(context, 'Code copied');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: Text(o['code']?.toString() ?? ''),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(o['description']?.toString() ?? 'Ride discount',
                          style: Theme.of(context).textTheme.titleSmall),
                      if (o['minFare'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Min fare ${money(o['minFare'])}',
                              style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
