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

class DriverHistoryScreen extends ConsumerStatefulWidget {
  const DriverHistoryScreen({super.key, this.showBack = true});
  final bool showBack;

  @override
  ConsumerState<DriverHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<DriverHistoryScreen> {
  String _filter = 'all'; // all | completed | cancelled

  bool _matches(Ride r) => switch (_filter) {
        'completed' => r.status == RideStatus.completed,
        'cancelled' => r.status.isCancelled,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_driverHistoryProvider);
    return Scaffold(
      appBar: RtAppBar(
        title: 'Trips',
        fallbackRoute: '/d/dashboard',
        showBack: widget.showBack,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (all) {
          final rides = all.where(_matches).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(_driverHistoryProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'completed', label: Text('Completed')),
                    ButtonSegment(value: 'cancelled', label: Text('Cancelled')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
                const SizedBox(height: 16),
                if (rides.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: EmptyState(
                        icon: Icons.history_rounded, title: 'No trips here'),
                  )
                else
                  ...rides.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TripCard(ride: r),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final cancelled = ride.status.isCancelled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(VehicleCategoryInfo.of(ride.vehicleCategory).emoji,
                style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ride.dropAddr ?? ride.ref,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${dateTimeLabel(ride.requestedAt)} · ${distance(ride.distanceM)}',
                    style:
                        const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              cancelled ? '—' : money(ride.finalFare ?? ride.estFare),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cancelled ? AppColors.inkSoft : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
