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

enum _Filter { all, upcoming, ongoing, completed, cancelled }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All trips',
        _Filter.upcoming => 'Upcoming',
        _Filter.ongoing => 'Ongoing',
        _Filter.completed => 'Completed',
        _Filter.cancelled => 'Cancelled',
      };

  IconData get icon => switch (this) {
        _Filter.all => Icons.directions_car_filled_rounded,
        _Filter.upcoming => Icons.schedule_rounded,
        _Filter.ongoing => Icons.sync_rounded,
        _Filter.completed => Icons.check_circle_outline_rounded,
        _Filter.cancelled => Icons.cancel_outlined,
      };

  bool matches(RideStatus s) => switch (this) {
        _Filter.all => true,
        // Not yet under way — still searching or a driver is en route.
        _Filter.upcoming => const {
            RideStatus.requested,
            RideStatus.searchingDriver,
            RideStatus.driverAssigned,
            RideStatus.driverArriving,
          }.contains(s),
        // Driver is with the rider or the trip is actively running.
        _Filter.ongoing => const {
            RideStatus.driverArrived,
            RideStatus.rideStarted,
            RideStatus.rideInProgress,
            RideStatus.driverCompleted,
            RideStatus.paymentPending,
          }.contains(s),
        _Filter.completed => s == RideStatus.completed,
        _Filter.cancelled => s.isCancelled || s == RideStatus.noDriversFound || s == RideStatus.paymentFailed,
      };
}

class RideHistoryScreen extends ConsumerStatefulWidget {
  const RideHistoryScreen({super.key});
  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  _Filter _filter = _Filter.all;

  Future<void> _pickFilter() async {
    final picked = await showModalBottomSheet<_Filter>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ..._Filter.values.map((f) => ListTile(
                  leading: Icon(f.icon, color: AppColors.primary),
                  title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: f == _filter ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(context, f),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _filter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_historyProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Bookings', fallbackRoute: '/c/home'),
      body: Column(
        children: [
          InkWell(
            onTap: _pickFilter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(_filter.icon, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_filter.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.textPrimary,
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load rides',
                subtitle: '$e',
              ),
              data: (rides) {
                final filtered = rides.where((r) => _filter.matches(r.status)).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: _filter == _Filter.all ? 'No rides yet' : 'No ${_filter.label.toLowerCase()} rides',
                    subtitle: 'Your rides show up here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(_historyProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => RideHistoryTile(ride: filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
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
