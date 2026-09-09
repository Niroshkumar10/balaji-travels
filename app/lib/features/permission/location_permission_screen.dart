import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';

/// Standalone permission-primer, reachable at /permission. Individual flows
/// (customer home, driver dashboard) also request in-context.
class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});
  @override
  ConsumerState<LocationPermissionScreen> createState() => _State();
}

class _State extends ConsumerState<LocationPermissionScreen> {
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    final r = await ref.read(locationServiceProvider).ensurePermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.granted) {
      final role = ref.read(authControllerProvider).role;
      context.go(role == AppRole.driver ? '/d/dashboard' : '/c/home');
    } else if (r.permanentlyDenied) {
      showError(context, 'Enable location for Sri Balaji Travels in Settings.');
      await ref.read(locationServiceProvider).openAppSettings();
    } else if (!r.serviceEnabled) {
      showError(context, 'Turn on location services.');
      await ref.read(locationServiceProvider).openLocationSettings();
    } else {
      showError(context, 'Location permission is needed to book rides.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.my_location_rounded, size: 96, color: AppColors.brand),
              const SizedBox(height: 28),
              Text('Allow location access', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              const Text(
                'Sri Balaji Travels uses your location to set your pickup point and to show your '
                'driver on the map in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, height: 1.4),
              ),
              const Spacer(),
              PrimaryButton(label: 'Allow location', busy: _busy, onPressed: _request),
              TextButton(
                onPressed: () {
                  final role = ref.read(authControllerProvider).role;
                  context.go(role == AppRole.driver ? '/d/dashboard' : '/c/home');
                },
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
