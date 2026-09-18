import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/realtime/socket_diagnostics.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';
import 'dashboard/driver_dashboard_screen.dart';
import 'driver_controller.dart';
import 'earnings/earnings_screen.dart';
import 'history/driver_history_screen.dart';
import 'onboarding/onboarding_entry.dart';
import 'onboarding/registration_checklist_screen.dart';
import 'profile/driver_profile_screen.dart';

/// The driver app's home: a persistent 4-tab bottom bar (Home · Earnings ·
/// Trips · Profile). Incoming ride offers and active trips are still full-screen
/// routes pushed on top of the shell — routed from here so they fire whatever
/// tab the driver is on.
///
/// Gated on real KYC approval: a driver who hasn't finished onboarding (or
/// whose application is still pending/rejected) never sees this shell at
/// all — landing here renders DriverOnboardingEntry instead, which routes
/// them to whichever stage (intro, checklist, or status) they're actually
/// at. Only once `kycApproved` and an active vehicle are on file does the
/// real "go online" dashboard show. Previously this shell rendered
/// unconditionally and only *nudged* toward setup with a card, which is why
/// a fresh driver could reach the online/offline dashboard immediately
/// after OTP with none of the onboarding steps done.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  StreamSubscription<PendingOffer>? _offerSub;
  int? _lastShownOfferId;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen to the discrete offer-alert stream directly, not a diffed state
    // snapshot — every ride:offer is its own event here, so there is no
    // before/after comparison that can miss one (see DriverController for
    // why the old diff-based trigger did). Subscribed once for the shell's
    // whole lifetime, so it keeps firing regardless of which tab is showing
    // or whether the offer screen itself is pushed on top.
    _offerSub = ref.read(driverControllerProvider.notifier).offerAlerts.listen((offer) {
      if (offer.rideId == _lastShownOfferId) return; // same ride re-announced — don't double-push
      _lastShownOfferId = offer.rideId;
      if (!mounted) return;
      SocketDiagLog.instance.add('navigating to offer popup /d/offer/${offer.rideId}');
      context.push('/d/offer/${offer.rideId}');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offerSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can pause the socket's own reconnect timer while backgrounded —
    // the moment the driver app is foregrounded again (opened from recents,
    // screen unlocked back into it, a call/notification dismissed), force a
    // reconnect check immediately rather than waiting for socket.io's own
    // backoff to eventually fire.
    if (state == AppLifecycleState.resumed) {
      SocketDiagLog.instance.add('app resumed — ensuring socket connection');
      ref.read(socketClientProvider).ensureConnected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(driverProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e')),
      ),
      data: (p) {
        if (p == null || !p.kycApproved) return const DriverOnboardingEntry();
        // KYC and vehicle are reviewed independently — an admin can approve a
        // driver's KYC before (or without) them ever adding a vehicle. That's
        // a real, valid state, not "hasn't started onboarding" — routing it
        // through DriverOnboardingEntry used to send an already-approved
        // driver straight to the "let's get started" intro wizard (it decides
        // which screen to show from on-device storage, which is empty for
        // this driver's real cause: no vehicle, not a fresh signup). Go
        // straight to the checklist instead, which already shows exactly one
        // real remaining step (Vehicle RC) from live backend data.
        if (!p.vehicles.any((v) => v.isActive)) return const RegistrationChecklistScreen();
        return _shell(context);
      },
    );
  }

  Widget _shell(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.ride != null &&
          next.ride!.status.isActive &&
          prev?.ride?.id != next.ride!.id) {
        context.push('/d/ride/${next.ride!.id}');
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      // The drawer lives on this Scaffold (not DriverHomeTab's own) so it
      // covers the whole screen when opened — including the bottom nav bar
      // below, which used to stay visible/tappable underneath it.
      drawer: const DriverDrawer(),
      body: IndexedStack(
        index: _tab,
        children: [
          DriverHomeTab(onMenuTap: () => _scaffoldKey.currentState?.openDrawer()),
          EarningsScreen(onBack: () => setState(() => _tab = 0)),
          DriverHistoryScreen(onBack: () => setState(() => _tab = 0)),
          DriverProfileScreen(onBack: () => setState(() => _tab = 0)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
