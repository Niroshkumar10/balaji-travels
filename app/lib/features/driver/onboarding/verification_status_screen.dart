import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';

/// Reflects the real `kycStatus` from the backend — an ops reviewer flips
/// this via the admin `/ops/drivers/:id/kyc` endpoint; nothing in the app
/// can approve or reject itself. Pull-to-refresh (or the retry button) just
/// re-fetches the driver profile to see if that's happened yet.
class VerificationStatusScreen extends ConsumerWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Application status')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load status',
              subtitle: '$e',
            ),
          ),
          data: (p) {
            if (p == null) return const Center(child: EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable'));
            return switch (p.kycStatus) {
              'approved' => _Approved(onStart: () => context.go('/d/dashboard')),
              'rejected' => _Rejected(onRetry: () => context.go('/d/onboarding/checklist')),
              _ => RefreshIndicator(
                  onRefresh: () async => ref.invalidate(driverProfileProvider),
                  child: _Pending(hasVehicle: p.vehicles.isNotEmpty),
                ),
            };
          },
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.hasVehicle});
  final bool hasVehicle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 12),
        Row(
          children: const [
            Text('Verification progress', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Spacer(),
            Text('75%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(value: 0.75, minHeight: 6, backgroundColor: AppColors.canvas, color: AppColors.primary),
        ),
        const SizedBox(height: 24),
        _StatusRow(label: 'Profile completed', done: true),
        _StatusRow(label: 'Documents submitted', done: true),
        _StatusRow(label: 'Vehicle verified', done: hasVehicle),
        const _StatusRow(label: 'Final verification', done: false, current: true),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
          child: const Row(
            children: [
              Icon(Icons.hourglass_bottom_rounded, color: AppColors.inkSoft),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Our team is reviewing your information. Pull to refresh once you expect an update.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.done, this.current = false});
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : (current ? Icons.hourglass_bottom_rounded : Icons.radio_button_unchecked_rounded),
            color: done ? AppColors.success : (current ? AppColors.secondary : AppColors.inkSoft),
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Approved extends StatelessWidget {
  const _Approved({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(radius: 44, backgroundColor: AppColors.cardSelectedBackground, child: Icon(Icons.check_rounded, color: AppColors.success, size: 44)),
          const SizedBox(height: 20),
          const Text("You're ready to drive!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Your driver account has been approved. Start accepting rides and earn with Sri Balaji Travels.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 28),
          PrimaryButton(label: 'Start driving', onPressed: onStart),
        ],
      ),
    );
  }
}

class _Rejected extends StatelessWidget {
  const _Rejected({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(radius: 44, backgroundColor: Color(0xFFFFF3E0), child: Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 44)),
          const SizedBox(height: 20),
          const Text('Document needs attention', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Your submission was rejected. Please review your documents and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Reason', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF92400E))),
                SizedBox(height: 6),
                Text(
                  'The licence number could not be read clearly. Please re-upload a clear photo of your driving licence.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          PrimaryButton(label: 'Upload again', onPressed: onRetry),
        ],
      ),
    );
  }
}
