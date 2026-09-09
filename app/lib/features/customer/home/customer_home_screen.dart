import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});
  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  LatLng _center = const LatLng(12.9716, 77.5946); // Bengaluru default
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locate();
      ref.read(rideSessionProvider.notifier).loadActive();
    });
  }

  Future<void> _locate() async {
    final perm = await ref.read(locationServiceProvider).ensurePermission();
    if (!perm.granted) {
      if (mounted) setState(() => _locating = false);
      return;
    }
    final pos = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) _center = LatLng(pos.latitude, pos.longitude);
    });
    _mapKey.currentState?.moveTo(_center);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(rideSessionProvider);
    final activeRide = session.ride;
    final name = ref.watch(authControllerProvider).name ?? 'there';

    return Scaffold(
      drawer: const _CustomerDrawer(),
      body: Stack(
        children: [
          MapView(
            key: _mapKey,
            initial: _center,
            myLocationEnabled: true,
            markers: {
              Marker(markerId: const MarkerId('me'), position: _center),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => _RoundBtn(
                      icon: Icons.menu_rounded,
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Spacer(),
                  _RoundBtn(
                    icon: Icons.my_location_rounded,
                    onTap: _locate,
                    busy: _locating,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activeRide != null && activeRide.status.isActive)
                      _ResumeBanner(ride: activeRide),
                    if (activeRide != null && activeRide.status.isActive)
                      const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hi $name, where are you going?',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => context.push('/c/where-to'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.canvas,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.search_rounded, color: AppColors.inkSoft),
                                    SizedBox(width: 10),
                                    Text('Where to?',
                                        style: TextStyle(color: AppColors.inkSoft, fontSize: 16)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _Shortcut(
                                  icon: Icons.home_rounded,
                                  label: 'Home',
                                  onTap: () => context.push('/c/where-to', extra: 'home'),
                                ),
                                const SizedBox(width: 10),
                                _Shortcut(
                                  icon: Icons.work_rounded,
                                  label: 'Work',
                                  onTap: () => context.push('/c/where-to', extra: 'work'),
                                ),
                                const SizedBox(width: 10),
                                _Shortcut(
                                  icon: Icons.bookmark_rounded,
                                  label: 'Saved',
                                  onTap: () => context.push('/c/saved-places'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/c/ride/${ride.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.directions_car_filled_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ride in progress',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(ride.status.label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.busy = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: 44,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
        ),
      ),
    );
  }
}

class _CustomerDrawer extends ConsumerWidget {
  const _CustomerDrawer();

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
                  auth.name?.isNotEmpty == true ? auth.name! : 'Rider',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text('+91 ${auth.mobile ?? ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _item(context, Icons.receipt_long_rounded, 'Your rides', '/c/history'),
          _item(context, Icons.local_offer_rounded, 'Offers', '/c/offers',
              color: AppColors.secondary),
          _item(context, Icons.bookmark_rounded, 'Saved places', '/c/saved-places'),
          _item(context, Icons.notifications_rounded, 'Notifications', '/c/notifications'),
          _item(context, Icons.person_rounded, 'Profile', '/c/profile'),
          _item(context, Icons.help_outline_rounded, 'Support', '/c/support'),
          const Spacer(),
          const Divider(height: 1),
          AppTile(
            icon: Icons.swap_horiz_rounded,
            title: 'Switch to Driver',
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
          // Capture the router BEFORE closing the drawer — popping the drawer
          // disposes this ListTile's context, and using it for push afterwards
          // is what made the pushed screen non-poppable ("back doesn't work").
          final router = GoRouter.of(context);
          Navigator.pop(context);
          router.push(route);
        },
      );
}
