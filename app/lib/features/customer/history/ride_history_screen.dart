import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _historyProvider = FutureProvider.autoDispose<List<Ride>>((ref) async {
  final res = await ref.watch(rideRepoProvider).list(limit: 50);
  return res.valueOrNull ?? [];
});

class RideHistoryScreen extends ConsumerWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Your rides', fallbackRoute: '/c/home'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load rides',
          subtitle: '$e',
        ),
        data: (rides) {
          if (rides.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No rides yet',
              subtitle: 'Your completed and cancelled rides show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(_historyProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rides.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => RideHistoryTile(ride: rides[i]),
            ),
          );
        },
      ),
    );
  }
}

class RideHistoryTile extends StatelessWidget {
  const RideHistoryTile({super.key, required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final cancelled = ride.status.isCancelled;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/c/ride-detail/${ride.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(VehicleCategoryInfo.of(ride.vehicleCategory).emoji,
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.dropAddr ?? 'Ride ${ride.ref}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateTimeLabel(ride.requestedAt),
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cancelled ? '—' : money(ride.finalFare ?? ride.estFare),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  StatusPill(
                    ride.status.label,
                    color: rideStatusColor(ride.status),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
