import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import 'rental_trip_controller.dart';

/// Driver's central place to manage future Rental/Trip assignments —
/// reachable from the drawer. Two tabs, same structure as the rider's
/// Upcoming Trips screen (upcoming_trips_screen.dart).
class RentalTripScreen extends ConsumerStatefulWidget {
  const RentalTripScreen({super.key});
  @override
  ConsumerState<RentalTripScreen> createState() => _RentalTripScreenState();
}

class _RentalTripScreenState extends ConsumerState<RentalTripScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rentalTripProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(rentalTripProvider);
    final rentals = rides.where((r) => r.serviceKind == 'rental').toList();
    final trips = rides.where((r) => r.serviceKind == 'trip').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: RtAppBar(
          title: 'Rental and Trip',
          fallbackRoute: '/d/dashboard',
          bottom: const TabBar(tabs: [Tab(text: 'Rental'), Tab(text: 'Trip')]),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => ref.read(rentalTripProvider.notifier).refresh(),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _BookingList(rides: rentals, emptyIcon: Icons.schedule_rounded, emptyTitle: 'No rental assignments'),
            _BookingList(rides: trips, emptyIcon: Icons.alt_route_rounded, emptyTitle: 'No trip assignments'),
          ],
        ),
      ),
    );
  }
}

class _BookingList extends ConsumerWidget {
  const _BookingList({required this.rides, required this.emptyIcon, required this.emptyTitle});
  final List<Ride> rides;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rides.isEmpty) {
      return EmptyState(icon: emptyIcon, title: emptyTitle, subtitle: 'Assignments from admin show up here.');
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(rentalTripProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rides.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _BookingCard(ride: rides[i]),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.ride});
  final Ride ride;

  String get _title => ride.rideType == 'rental'
      ? 'Rental${ride.rentalPackageHours != null ? ' · ${ride.rentalPackageHours} Hour${ride.rentalPackageHours == 1 ? '' : 's'}' : ''}'
      : ride.rideType == 'round_trip'
          ? 'Round Trip'
          : 'Trip';

  String get _statusLabel => switch (ride.assignmentStage) {
        RideAssignmentStage.awaitingDriverConfirmation => 'Confirm required',
        RideAssignmentStage.reserved => 'Reserved',
        RideAssignmentStage.live => 'On trip',
        _ => ride.status.label,
      };

  Color get _statusColor => switch (ride.assignmentStage) {
        RideAssignmentStage.awaitingDriverConfirmation => AppColors.secondaryDark,
        RideAssignmentStage.reserved => AppColors.info,
        _ => AppColors.rideStarted,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/d/rental-trip/${ride.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title, style: t.titleSmall),
                        const SizedBox(height: 2),
                        Text(dateTimeLabel(ride.scheduledAt ?? ride.requestedAt),
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(money(ride.finalFare ?? ride.estFare), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(ride.pickupAddr ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatusPill(_statusLabel, color: _statusColor),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
