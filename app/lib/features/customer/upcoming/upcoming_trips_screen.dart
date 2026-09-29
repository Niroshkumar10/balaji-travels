import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import '../active_rides_controller.dart';
import 'upcoming_trip_card.dart';

/// Rider's "Upcoming Trips" screen (drawer → Upcoming Trips), with Rental
/// and Trip tabs — Rental/Trip bookings intentionally don't clutter the
/// home screen as "ride in progress" cards (see customer_home_screen.dart's
/// Local-only filter); this is where they live instead.
///
/// Reuses activeRidesProvider (already powers the home screen's Local card
/// and refreshes on the same ride-lifecycle socket events) rather than a
/// separate provider — it already returns every non-terminal ride across
/// all types, this screen just filters to non-local.
class UpcomingTripsScreen extends ConsumerStatefulWidget {
  const UpcomingTripsScreen({super.key});
  @override
  ConsumerState<UpcomingTripsScreen> createState() => _UpcomingTripsScreenState();
}

class _UpcomingTripsScreenState extends ConsumerState<UpcomingTripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRidesProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(activeRidesProvider);
    final rentals = rides.where((r) => r.serviceKind == 'rental').toList();
    final trips = rides.where((r) => r.serviceKind == 'trip').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: RtAppBar(
          title: 'Upcoming Trips',
          fallbackRoute: '/c/home',
          bottom: const TabBar(tabs: [Tab(text: 'Rental'), Tab(text: 'Trip')]),
        ),
        body: TabBarView(
          children: [
            _TripList(rides: rentals, emptyIcon: Icons.schedule_rounded, emptyTitle: 'No upcoming rentals'),
            _TripList(rides: trips, emptyIcon: Icons.alt_route_rounded, emptyTitle: 'No upcoming trips'),
          ],
        ),
      ),
    );
  }
}

class _TripList extends ConsumerWidget {
  const _TripList({required this.rides, required this.emptyIcon, required this.emptyTitle});
  final List rides;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rides.isEmpty) {
      return EmptyState(icon: emptyIcon, title: emptyTitle, subtitle: 'Bookings you make will show up here.');
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(activeRidesProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rides.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => UpcomingTripCard(ride: rides[i]),
      ),
    );
  }
}
