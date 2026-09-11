import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';

/// Shown immediately after submitting the application — a real full screen
/// (not a dialog), matching the reference exactly: application ID, four
/// sections all "Under review", Got it → verification status.
class ApplicationSubmittedScreen extends StatelessWidget {
  const ApplicationSubmittedScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const CircleAvatar(radius: 40, backgroundColor: AppColors.cardSelectedBackground, child: Icon(Icons.check_rounded, color: AppColors.success, size: 40)),
              const SizedBox(height: 20),
              const Text('Application submitted', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                "We're reviewing your information. This may take a few hours.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Application ID', style: TextStyle(color: AppColors.inkSoft)),
                        const Spacer(),
                        Text('#$applicationId', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const Divider(height: 24),
                    for (final s in const ['Profile', 'Documents', 'Vehicle', 'Payment'])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600))),
                            const Text('Under review', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(label: 'Got it', onPressed: () => context.go('/d/onboarding/status')),
            ],
          ),
        ),
      ),
    );
  }
}
