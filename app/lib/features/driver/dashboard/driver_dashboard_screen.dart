import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';
import '../earnings/earnings_controller.dart';
import '../onboarding/payment_details_screen.dart';
import '../profile/driver_account_detail_screen.dart';

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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
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
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: const _DriverDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
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
                ],
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
                  if (onTrip) _ResumeTrip(rideId: state.ride!.id, label: state.ride!.status.label),
                ],
              ),
            ),
            if (!onTrip)
              _StatusPanel(
                online: state.online,
                busy: state.busy,
                onGoOnline: _goOnline,
                onGoOffline: _goOffline,
                trips: earnings.valueOrNull?.trips,
                net: earnings.valueOrNull?.net,
              ),
          ],
        ),
      ),
    );
  }
}

/// Anchored to the bottom (not floating mid-map, not a full-width opaque bar)
/// so the live map stays visible behind and around it — a thin strip instead
/// of the large centred card + separate full-width button this replaced.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.online,
    required this.busy,
    required this.onGoOnline,
    required this.onGoOffline,
    required this.trips,
    required this.net,
  });
  final bool online;
  final bool busy;
  final VoidCallback onGoOnline;
  final VoidCallback onGoOffline;
  final int? trips;
  final double? net;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      elevation: 8,
      shadowColor: AppColors.cardShadow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        // No LoadingOverlay here — that scrim used to gray out this whole
        // panel while the request was in flight. Busy state now lives only
        // on the button itself (see PrimaryButton's own `busy`), so the pill
        // and stats stay fully visible and only the button shows a spinner.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            StatusPill(
              online ? "You're online" : "You're offline",
              color: online ? AppColors.success : AppColors.inkSoft,
            ),
            const SizedBox(height: 10),
            Text(
              online ? 'Looking for nearby rides…' : 'Go online to receive ride requests',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            if (online) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _Stat(icon: Icons.calendar_today_rounded, label: 'Today', value: money(net ?? 0))),
                  const SizedBox(height: 32, child: VerticalDivider(width: 1)),
                  Expanded(child: _Stat(icon: Icons.card_travel_rounded, label: 'Trips', value: '${trips ?? 0}', valueFirst: true)),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Go Offline', icon: Icons.stop_rounded, busy: busy, onPressed: onGoOffline),
            ] else ...[
              const SizedBox(height: 16),
              PrimaryButton(label: 'Go Online', busy: busy, onPressed: onGoOnline),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.inkSoft),
                  const SizedBox(width: 8),
                  Text('Today  ${money(net ?? 0)}  ·  ${trips ?? 0} trips', style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, this.valueFirst = false});
  final IconData icon;
  final String label;
  final String value;

  /// Trips-style stat shows the number beside the icon with the label
  /// underneath; the earnings stat shows the label beside the icon with the
  /// amount underneath — matches the reference exactly rather than forcing
  /// both stats into one shape.
  final bool valueFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: AppColors.inkSoft),
            const SizedBox(width: 6),
            Text(valueFirst ? value : label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Text(valueFirst ? label : value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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

const _languages = ['English', 'தமிழ் (Tamil)', 'తెలుగు (Telugu)', 'ಕನ್ನಡ (Kannada)', 'हिंदी (Hindi)'];

/// The driver's account menu — brand header + driver phone number, then
/// everything about the account (personal info, vehicle, documents, bank
/// details, language, notifications, safety, help, wallet & payouts) plus
/// Switch to Ride / Log out. Opened via the hamburger on the Home tab's top
/// bar, mirroring the rider side's own drawer (_CustomerDrawer).
class _DriverDrawer extends ConsumerWidget {
  const _DriverDrawer();

  Future<void> _pickLanguage(BuildContext context) async {
    final current = (await DriverOnboardingStore.get())['language'] as String?;
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _languages
              .map((l) => ListTile(
                    title: Text(l),
                    trailing: l == current ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () => Navigator.pop(context, l),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) await DriverOnboardingStore.patch({'language': picked});
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go('/role');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'Sri Balaji ',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      TextSpan(
                        text: 'Travels',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      ),
                    ]),
                  ),
                  if (auth.mobile != null) ...[
                    const SizedBox(height: 12),
                    Text('+91 ${auth.mobile}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  AppTile(
                    icon: Icons.person_rounded,
                    title: 'Personal information',
                    onTap: () => _openAccountDetail(context, 'personal'),
                  ),
                  AppTile(
                    icon: Icons.directions_car_filled_rounded,
                    title: 'Vehicle',
                    onTap: () => _openAccountDetail(context, 'vehicle'),
                  ),
                  AppTile(
                    icon: Icons.description_rounded,
                    title: 'Documents',
                    onTap: () => _openAccountDetail(context, 'documents'),
                  ),
                  AppTile(
                    icon: Icons.account_balance_rounded,
                    title: 'Bank details',
                    onTap: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.push(MaterialPageRoute(builder: (_) => const PaymentDetailsScreen()));
                    },
                  ),
                  AppTile(icon: Icons.language_rounded, title: 'Language', onTap: () => _pickLanguage(context)),
                  AppTile(
                    icon: Icons.notifications_rounded,
                    title: 'Notification',
                    onTap: () => _push(context, '/d/notifications'),
                  ),
                  AppTile(
                    icon: Icons.shield_rounded,
                    title: 'Safety',
                    iconColor: AppColors.error,
                    onTap: () => _push(context, '/d/safety'),
                  ),
                  AppTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & support',
                    onTap: () => _push(context, '/d/safety'),
                  ),
                  AppTile(
                    icon: Icons.savings_rounded,
                    title: 'Wallet & payouts',
                    iconColor: AppColors.secondary,
                    onTap: () => _push(context, '/d/wallet'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            AppTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch to Ride',
              iconColor: AppColors.info,
              onTap: () => _logout(context, ref),
            ),
            AppTile(
              icon: Icons.logout_rounded,
              title: 'Log out',
              iconColor: AppColors.error,
              onTap: () => _logout(context, ref),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Captures the router/navigator BEFORE closing the drawer — popping it
  // disposes this tile's context, and using it for navigation afterwards is
  // what makes the pushed screen non-poppable ("back doesn't work").
  void _push(BuildContext context, String route) {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(route);
  }

  void _openAccountDetail(BuildContext context, String section) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => DriverAccountDetailScreen(initialExpanded: section)));
  }
}
