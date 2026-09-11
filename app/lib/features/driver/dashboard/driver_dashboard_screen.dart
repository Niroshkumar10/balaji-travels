import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
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
    final session = ref.watch(sessionProvider);
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
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: () => context.push('/d/notifications'),
                  ),
                  const CircleAvatar(radius: 18, backgroundColor: AppColors.canvas, child: Icon(Icons.person, color: AppColors.inkSoft)),
                ],
              ),
            ),
            if (AppConfig.isDev)
              Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  'build: $socketClientBuildMarker\n'
                  'session: role=${session.role?.name} userId=${session.userId} mobile=${session.mobile}\n'
                  'socket: ${state.socketState}   ·   last event: ${state.lastEvent ?? "(none)"}'
                  '${state.offer != null ? "   ·   OFFER #${state.offer!.rideId}" : ""}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MapView(
                    key: _mapKey,
                    initial: _center,
                    myLocationEnabled: true,
                  ),
                  if (onTrip)
                    _ResumeTrip(rideId: state.ride!.id, label: state.ride!.status.label)
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
