import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';
import 'intro_pages.dart';
import 'registration_checklist_screen.dart';
import 'verification_status_screen.dart';

/// Where a driver lands on `/d/setup` (and `/d/onboarding`) — decides which
/// stage of the flow to show based on real profile state plus the local
/// checklist progress, so a driver who backs out mid-flow (or reopens the
/// app) picks up where they left off instead of restarting.
class DriverOnboardingEntry extends ConsumerWidget {
  const DriverOnboardingEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(driverProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e')),
      ),
      data: (p) {
        if (p == null) {
          return const Scaffold(body: Center(child: EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable')));
        }
        return FutureBuilder<Map<String, dynamic>>(
          future: DriverOnboardingStore.get(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final local = snap.data!;
            final startedIntro = (p.name?.isNotEmpty == true) || local['vehicleCategory'] != null;
            if (!startedIntro) return const DriverIntroPages();
            if (local['submitted'] == true) return const VerificationStatusScreen();
            return const RegistrationChecklistScreen();
          },
        );
      },
    );
  }
}
