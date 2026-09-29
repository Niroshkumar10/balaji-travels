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

final _driverHistoryProvider = FutureProvider.autoDispose<List<Ride>>((ref) async {
  final res = await ref.watch(rideRepoProvider).list(limit: 50);
  return res.valueOrNull ?? const [];
});

class DriverHistoryScreen extends ConsumerStatefulWidget {
  const DriverHistoryScreen({super.key, this.showBack = true, this.onBack});
  final bool showBack;

  /// When this screen is a bottom-nav tab rather than a pushed route, pass a
  /// callback that switches the shell back to Home instead of trying to pop.
  final VoidCallback? onBack;

  @override
  ConsumerState<DriverHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<DriverHistoryScreen> {
  String _range = 'today'; // today | week | all
  String _filter = 'all'; // all | completed | cancelled

  bool _matchesStatus(Ride r) => switch (_filter) {
        'completed' => r.status == RideStatus.completed,
        'cancelled' => r.status.isCancelled,
        _ => true,
      };

  bool _matchesRange(Ride r) {
    // historyAt (core/models/ride.dart) is completedAt/cancelledAt/requestedAt
    // depending on how the ride actually ended up — never scheduledAt, which
    // is a future target pickup time unrelated to when it was actually
    // driven/cancelled (a rental's scheduled slot and its real completion
    // can land on different days — that mismatch is exactly what made a
    // reserved-for-later booking, or a trip completed on a different day,
    // show up under "Today" before this fix).
    final at = r.historyAt;
    if (at == null || _range == 'all') return true;
    final now = DateTime.now();
    if (_range == 'today') {
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }
    return now.difference(at).inDays < 7; // week
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_driverHistoryProvider);
    return Scaffold(
      appBar: RtAppBar(
        title: 'Trips',
        fallbackRoute: '/d/dashboard',
        showBack: widget.showBack,
        onBack: widget.onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_driverHistoryProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (all) {
          final rides = all.where(_matchesStatus).where(_matchesRange).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(_driverHistoryProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', label: Text('Today')),
                    ButtonSegment(value: 'week', label: Text('This week')),
                    ButtonSegment(value: 'all', label: Text('All')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 10),
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
                    child: EmptyState(icon: Icons.history_rounded, title: 'No trips here'),
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
    final completed = ride.status == RideStatus.completed;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/d/trip-detail/${ride.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(VehicleCategoryInfo.of(ride.vehicleCategory).emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride.dropAddr ?? ride.ref, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      // historyAt: completedAt/cancelledAt/requestedAt as
                      // appropriate — never scheduledAt (see core/models/
                      // ride.dart's doc comment; that's a future target
                      // slot, not when this row actually happened).
                      '${dateTimeLabel(ride.historyAt)} · ${distance(ride.distanceM)}',
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cancelled ? '—' : money(ride.finalFare ?? ride.estFare),
                    style: TextStyle(fontWeight: FontWeight.w800, color: cancelled ? AppColors.inkSoft : AppColors.success),
                  ),
                  // The real status, not a hardcoded "Completed" for
                  // anything that merely isn't cancelled — a still-active
                  // or reserved-for-later ride (e.g. an accepted future
                  // Rental awaiting its pickup time) is neither, and
                  // showing it as "Completed" is exactly what made a trip
                  // that hasn't happened yet count toward today's total.
                  Text(
                    completed ? 'Completed' : (cancelled ? 'Cancelled' : ride.status.label),
                    style: TextStyle(
                      color: completed || cancelled ? AppColors.inkSoft : rideStatusColor(ride.status),
                      fontSize: 11,
                      fontWeight: completed || cancelled ? FontWeight.normal : FontWeight.w700,
                    ),
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
