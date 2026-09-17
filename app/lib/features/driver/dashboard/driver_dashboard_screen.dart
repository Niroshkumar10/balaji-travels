import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../driver_controller.dart';
import '../earnings/earnings_controller.dart';

/// Home tab of the driver shell. A real, live map fills the background —
/// centred on the driver's own GPS fix via positionStreamProvider, the same
/// location plumbing the customer home screen and the in-trip map use — with
/// the online/offline status card floating on top of it.
class DriverHomeTab extends ConsumerStatefulWidget {
  const DriverHomeTab({super.key});
  @override
  ConsumerState<DriverHomeTab> createState() => _DriverHomeTabState();
}

class _DriverHomeTabState extends ConsumerState<DriverHomeTab> {
  final _mapKey = GlobalKey<MapViewState>();
  LatLng _center = const LatLng(12.9716, 77.5946); // fallback until GPS fixes
  bool _hasFix = false;

  Future<void> _goOnline() async {
    final err = await ref.read(driverControllerProvider.notifier).goOnline();
    if (err != null && mounted) showError(context, err);
  }

  Future<void> _goOffline() async {
    final err = await ref.read(driverControllerProvider.notifier).goOffline();
    if (err != null && mounted) showError(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverControllerProvider);
    final earnings = ref.watch(todayEarningsProvider);
    final onTrip = state.ride != null && state.ride!.status.isActive;

    ref.listen(positionStreamProvider, (prev, next) {
      final p = next.valueOrNull;
      if (p == null || !mounted) return;
      _center = LatLng(p.latitude, p.longitude);
      final firstFix = !_hasFix;
      if (firstFix) setState(() => _hasFix = true);
      _mapKey.currentState?.moveTo(_center, zoom: 16);
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  const Text('Sri Balaji Travels', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
                  const Spacer(),
                  // TEMPORARY: opens the in-app Socket.IO diagnostic log
                  // viewer (no ADB needed). Remove once the driver-side
                  // socket-connection investigation is closed out.
                  IconButton(
                    icon: const Icon(Icons.bug_report_outlined),
                    tooltip: 'Socket diagnostics',
                    onPressed: () => context.push('/d/diagnostics'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: () => context.push('/d/notifications'),
                  ),
                  const CircleAvatar(radius: 18, backgroundColor: AppColors.canvas, child: Icon(Icons.person, color: AppColors.inkSoft)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                // Manual fallback for whenever a newly assigned ride (in
                // particular one created from the Admin Panel, which has no
                // socket connection of its own and only gets a chance to
                // notify a live one) hasn't shown up on its own yet — pull
                // down to force the same fetch loadActive() does on cold
                // start.
                onRefresh: () => ref.read(driverControllerProvider.notifier).loadActive(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MapView(
                            key: _mapKey,
                            initial: _center,
                            myLocationEnabled: true,
                          ),
                          if (onTrip)
                            state.ride!.status == RideStatus.driverAssigned
                                ? _NewBookingCard(ride: state.ride!, rider: state.rider)
                                : _ResumeTrip(rideId: state.ride!.id, label: state.ride!.status.label)
                          else
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: _StatusCard(
                                  online: state.online,
                                  busy: state.busy,
                                  onGoOffline: _goOffline,
                                  earnings: earnings.maybeWhen(
                                    data: (s) => 'Trips today: ${s.trips}  ·  Earned: ${money(s.net)}',
                                    orElse: () => null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!onTrip && !state.online)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: LoadingOverlay(
                  busy: state.busy,
                  child: PrimaryButton(label: 'Go Online', onPressed: _goOnline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.online,
    required this.busy,
    required this.onGoOffline,
    required this.earnings,
  });
  final bool online;
  final bool busy;
  final VoidCallback onGoOffline;
  final String? earnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 48, backgroundColor: AppColors.canvas, child: Icon(Icons.person, size: 48, color: AppColors.inkSoft)),
          const SizedBox(height: 14),
          StatusPill(
            online ? "You're online" : "You're offline",
            color: online ? AppColors.success : AppColors.primary,
          ),
          const SizedBox(height: 14),
          if (online) ...[
            const Text("You're online", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              "You're now available to receive ride requests",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.radio_button_unchecked_rounded, color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Text('Searching for rides…', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (earnings != null) ...[
              const SizedBox(height: 20),
              Text(earnings!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: busy ? null : onGoOffline,
              child: const Text('Go offline'),
            ),
          ] else
            const Text(
              "You miss your nearest ride request?\nYou're offline. Go online to receive ride requests.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
        ],
      ),
    );
  }
}

/// Shown on the dashboard the moment a ride reaches DRIVER_ASSIGNED — same
/// status a normal accepted offer lands the driver in, but this is the state
/// where an Admin Panel call-in booking (no Accept step, no Pending Ride
/// Card — assigned directly, see [[dispatchService]]) is what a driver
/// notices first, since they were never shown an offer to accept. Pull-to-
/// refresh above is the fallback if this doesn't appear on its own from the
/// live socket update.
///
/// "Start Journey" continues into the exact same ride screen and the exact
/// same normal flow (Start navigation to pickup → Enroute → Arrived → OTP →
/// Start Trip → Complete) as any other assigned ride — this card is only a
/// clearer entry point into it, not a different flow.
class _NewBookingCard extends StatelessWidget {
  const _NewBookingCard({required this.ride, this.rider});
  final Ride ride;
  final RiderInfo? rider;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_car_filled_rounded, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('New booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const Spacer(),
                    if (ride.estFare != null)
                      Text(money(ride.estFare!), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
                if (rider?.name != null) ...[
                  const SizedBox(height: 4),
                  Text(rider!.name, style: const TextStyle(color: AppColors.inkSoft)),
                ],
                const SizedBox(height: 14),
                _AddrLine(icon: Icons.trip_origin_rounded, color: AppColors.success, text: ride.pickupAddr ?? 'Pickup point'),
                const SizedBox(height: 6),
                _AddrLine(icon: Icons.place_rounded, color: AppColors.error, text: ride.dropAddr ?? 'Drop point'),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Start Journey',
                  onPressed: () => context.push('/d/ride/${ride.id}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddrLine extends StatelessWidget {
  const _AddrLine({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _ResumeTrip extends StatelessWidget {
  const _ResumeTrip({required this.rideId, required this.label});
  final int rideId;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/d/ride/$rideId'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
