import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common_widgets.dart';
import 'dashboard/driver_dashboard_screen.dart';
import 'driver_controller.dart';
import 'earnings/earnings_screen.dart';
import 'history/driver_history_screen.dart';
import 'onboarding/onboarding_entry.dart';
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

class _DriverShellState extends ConsumerState<DriverShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(driverProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e')),
      ),
      data: (p) {
        final approved = p != null && p.kycApproved && p.vehicles.any((v) => v.isActive);
        if (!approved) return const DriverOnboardingEntry();
        return _shell(context);
      },
    );
  }

  Widget _shell(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.offer != null && prev?.offer == null) {
        context.push('/d/offer/${next.offer!.rideId}');
      }
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
