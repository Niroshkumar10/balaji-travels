import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';

/// Reached right after OTP verify (before Home) — the explicit, reliable way
/// to trigger the OS location permission dialog, since the map's own
/// in-context request (on first building Home) isn't a dependable enough
/// trigger on every device.
class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});
  @override
  ConsumerState<LocationPermissionScreen> createState() => _State();
}

class _State extends ConsumerState<LocationPermissionScreen> {
  // True only for the brief initial silent check below — kept separate from
  // the "Allow location" button's own busy state so a returning user who
  // already granted permission never sees the primer UI flash on screen.
  bool _checking = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _skipIfAlreadyGranted();
  }

  /// A returning driver/rider who already granted location shouldn't see
  /// this primer again on every login — only ask when it's actually still
  /// undecided/denied. `checkPermission` alone never raises the OS dialog,
  /// so this is safe to call without the "Allow location" button.
  Future<void> _skipIfAlreadyGranted() async {
    final perm = await Geolocator.checkPermission();
    if (!mounted) return;
    final granted = perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    if (granted) {
      _goHome();
    } else {
      setState(() => _checking = false);
    }
  }

  void _goHome() {
    final role = ref.read(authControllerProvider).role;
    context.go(role == AppRole.driver ? '/d/dashboard' : '/c/home');
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final r = await ref.read(locationServiceProvider).ensurePermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.granted) {
      _goHome();
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
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
              TextButton(onPressed: _goHome, child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
  }
}
