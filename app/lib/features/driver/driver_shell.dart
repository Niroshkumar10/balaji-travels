import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dashboard/driver_dashboard_screen.dart';
import 'driver_controller.dart';
import 'earnings/earnings_screen.dart';
import 'history/driver_history_screen.dart';
import 'profile/driver_profile_screen.dart';

/// The driver app's home: a persistent 4-tab bottom bar (Home · Earnings ·
/// Trips · Profile). Incoming ride offers and active trips are still full-screen
/// routes pushed on top of the shell — routed from here so they fire whatever
/// tab the driver is on.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  late int _tab = widget.initialTab;
  StreamSubscription<PendingOffer>? _offerSub;
  int? _lastShownOfferId;

  @override
  void initState() {
    super.initState();
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
      // ignore: avoid_print
      print('[RT-DRIVER] navigating to offer popup /d/offer/${offer.rideId}');
      context.push('/d/offer/${offer.rideId}');
    });
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.ride != null &&
          next.ride!.status.isActive &&
          prev?.ride?.id != next.ride!.id) {
        context.push('/d/ride/${next.ride!.id}');
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          DriverHomeTab(),
          EarningsScreen(showBack: false),
          DriverHistoryScreen(showBack: false),
          DriverProfileScreen(showBack: false),
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
