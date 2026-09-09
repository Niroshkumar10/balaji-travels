import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _driverHistoryProvider = FutureProvider.autoDispose<List<Ride>>((ref) async {
  final res = await ref.watch(rideRepoProvider).list(limit: 50);
  return res.valueOrNull ?? const [];
});

class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_driverHistoryProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Trip history', fallbackRoute: '/d/dashboard'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (rides) {
          if (rides.isEmpty) {
            return const EmptyState(icon: Icons.history_rounded, title: 'No trips yet');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(_driverHistoryProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rides.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = rides[i];
                final cancelled = r.status.isCancelled;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text(VehicleCategoryInfo.of(r.vehicleCategory).emoji,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.dropAddr ?? r.ref,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall),
                              Text(
                                '${dateTimeLabel(r.requestedAt)} · ${distance(r.distanceM)}',
                                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          cancelled ? '—' : money(r.finalFare ?? r.estFare),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cancelled ? AppColors.inkSoft : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
