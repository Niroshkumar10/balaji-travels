import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';
import '../earnings/earnings_controller.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});
  @override
  ConsumerState<DriverDashboardScreen> createState() => _State();
}

class _State extends ConsumerState<DriverDashboardScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  LatLng _center = const LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null || !mounted) return;
    setState(() => _center = LatLng(pos.latitude, pos.longitude));
    _mapKey.currentState?.moveTo(_center);
  }

  @override
  Widget build(BuildContext context) {
    // route to an incoming offer / active ride
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.offer != null && prev?.offer == null) {
        context.push('/d/offer/${next.offer!.rideId}');
      }
      if (next.ride != null && next.ride!.status.isActive && prev?.ride?.id != next.ride!.id) {
        context.push('/d/ride/${next.ride!.id}');
      }
    });

    final state = ref.watch(driverControllerProvider);
    final profileAsync = ref.watch(driverProfileProvider);
    final earnings = ref.watch(todayEarningsProvider);

    return Scaffold(
      drawer: const _DriverDrawer(),
      body: Stack(
        children: [
          MapView(key: _mapKey, initial: _center, myLocationEnabled: true),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => _Round(
                      icon: Icons.menu_rounded,
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Spacer(),
                  earnings.maybeWhen(
                    data: (s) => Chip(
                      avatar: const Icon(Icons.account_balance_wallet_rounded, size: 16),
                      label: Text('Today ${money(s.net)}'),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: profileAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (p) {
                    if (p == null) return const SizedBox.shrink();
                    final blocked = !p.kycApproved || p.vehicles.every((v) => !v.isActive);
                    if (blocked) {
                      return _SetupCard(
                        reason: !p.kycApproved
                            ? (p.kycStatus == 'pending'
                                ? 'Your account is under review.'
                                : 'KYC not approved.')
                            : 'Add an active vehicle to start driving.',
                      );
                    }
                    if (state.ride != null && state.ride!.status.isActive) {
                      return _ResumeCard(rideId: state.ride!.id, label: state.ride!.status.label);
                    }
                    return _OnlineCard(state: state);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineCard extends ConsumerWidget {
  const _OnlineCard({required this.state});
  final DriverState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = state.online;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  online ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                  color: online ? AppColors.success : AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(online ? 'You\'re online' : 'You\'re offline',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        online ? 'Waiting for ride requests…' : 'Go online to receive rides',
                        style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: online,
                  onChanged: state.busy
                      ? null
                      : (v) async {
                          final err = v
                              ? await ref.read(driverControllerProvider.notifier).goOnline()
                              : await ref.read(driverControllerProvider.notifier).goOffline();
                          if (err != null && context.mounted) showError(context, err);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.rideId, required this.label});
  final int rideId;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.brand,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/d/ride/$rideId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.navigation_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active trip',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.assignment_rounded, size: 36, color: AppColors.info),
            const SizedBox(height: 8),
            Text(reason, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Open setup',
              onPressed: () => context.push('/d/setup'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(height: 44, width: 44, child: Icon(icon)),
      ),
    );
  }
}

class _DriverDrawer extends ConsumerWidget {
  const _DriverDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  auth.name?.isNotEmpty == true ? auth.name! : 'Driver',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text('+91 ${auth.mobile ?? ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _item(context, Icons.account_balance_wallet_rounded, 'Earnings', '/d/earnings',
              color: AppColors.secondary),
          _item(context, Icons.savings_rounded, 'Wallet & payouts', '/d/wallet'),
          _item(context, Icons.history_rounded, 'Trip history', '/d/history'),
          _item(context, Icons.notifications_rounded, 'Notifications', '/d/notifications'),
          _item(context, Icons.person_rounded, 'Profile & vehicle', '/d/profile'),
          const Spacer(),
          const Divider(height: 1),
          AppTile(
            icon: Icons.swap_horiz_rounded,
            title: 'Switch to Ride',
            iconColor: AppColors.info,
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/role');
            },
          ),
          AppTile(
            icon: Icons.logout_rounded,
            title: 'Log out',
            iconColor: AppColors.error,
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/role');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, String route,
          {Color color = AppColors.primary}) =>
      AppTile(
        icon: icon,
        title: label,
        iconColor: color,
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.pop(context);
          router.push(route);
        },
      );
}
