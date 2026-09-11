import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';
import 'doc_capture_screen.dart';
import 'insurance_screen.dart';
import 'payment_details_screen.dart';
import 'vehicle_details_screen.dart';

/// The registration hub — mirrors the reference's checklist: personal info
/// is already done by the time a driver gets here (the intro pages collect
/// it), Driving Licence / Profile picture / Identity verification are one
/// photo each, and Vehicle RC bundles the rest of the vehicle paperwork
/// (details, insurance, payout info) as a short sequence.
class RegistrationChecklistScreen extends ConsumerStatefulWidget {
  const RegistrationChecklistScreen({super.key});
  @override
  ConsumerState<RegistrationChecklistScreen> createState() => _RegistrationChecklistScreenState();
}

class _RegistrationChecklistScreenState extends ConsumerState<RegistrationChecklistScreen> {
  Set<String> _done = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final done = await DriverOnboardingStore.doneSteps();
    if (!mounted) return;
    setState(() {
      _done = done;
      _loading = false;
    });
  }

  Future<void> _markDone(String step) async {
    await DriverOnboardingStore.setStepDone(step, true);
    if (mounted) setState(() => _done = {..._done, step});
  }

  Future<void> _openDoc(
    String step, {
    required String title,
    required List<String> requirements,
    String? heading,
    String? description,
    String uploadLabel = 'Upload',
    bool circular = false,
    bool dashedDropzone = false,
    bool primaryOpensCamera = false,
  }) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocCaptureScreen(
          title: title,
          requirements: requirements,
          heading: heading,
          description: description,
          uploadLabel: uploadLabel,
          circular: circular,
          dashedDropzone: dashedDropzone,
          primaryOpensCamera: primaryOpensCamera,
        ),
      ),
    );
    if (ok == true) await _markDone(step);
  }

  Future<void> _openIdentity() async {
    final choice = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _IdentityChooserScreen()),
    );
    if (choice == null || !mounted) return;
    await _openDoc(
      'identity',
      title: choice == 'aadhaar' ? 'Upload Aadhaar' : 'Upload ID',
      heading: choice == 'aadhaar' ? 'Upload your Aadhaar card' : 'Upload your identity document',
      requirements: const ['Clear photo', 'All details visible', 'No glare'],
      uploadLabel: choice == 'aadhaar' ? 'Upload Aadhaar' : 'Upload ID',
      dashedDropzone: true,
    );
  }

  Future<void> _openVehicleSequence() async {
    final vehicleOk = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const DocCaptureScreen(
          title: 'Vehicle RC',
          heading: 'Upload your vehicle Registration Certificate',
          requirements: ['Valid RC', 'Vehicle number visible'],
          uploadLabel: 'Upload RC',
          dashedDropzone: true,
        ),
      ),
    );
    if (vehicleOk != true || !mounted) return;

    final detailsOk = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const VehicleDetailsScreen()));
    if (detailsOk != true || !mounted) return;

    final insuranceOk = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const InsuranceScreen()));
    if (insuranceOk != true || !mounted) return;

    final paymentOk = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PaymentDetailsScreen()));
    if (paymentOk != true || !mounted) return;

    await _markDone('vehicle_rc');
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Complete your driver profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
              data: (p) {
                final hasVehicle = p != null && p.vehicles.isNotEmpty;
                final List<(String, String, bool, Future<void> Function()?)> items = [
                  ('profile', 'Personal information', p?.name?.isNotEmpty == true, null),
                  ('license', 'Driving Licence', _done.contains('license'), () => _openDoc(
                        'license',
                        title: 'Driving Licence',
                        description: "We need your valid driving licence to verify that you're eligible to drive.",
                        requirements: const ['Valid licence', 'Name should match your profile', 'Clear photo', 'All details must be readable'],
                        uploadLabel: 'Upload Licence',
                      )),
                  ('photo', 'Profile picture', _done.contains('photo'), () => _openDoc(
                        'photo',
                        title: 'Add a profile photo',
                        heading: 'Add a profile photo',
                        description: 'Your photo will be shown to customers when you receive a ride.',
                        requirements: const ['Face clearly visible', 'No sunglasses', 'Good lighting', 'No group photo'],
                        uploadLabel: 'Take Photo',
                        circular: true,
                        primaryOpensCamera: true,
                      )),
                  ('identity', 'Identity verification', _done.contains('identity'), _openIdentity),
                  ('vehicle_rc', 'Vehicle RC', hasVehicle && _done.contains('vehicle_rc'), _openVehicleSequence),
                ];
                final completed = items.where((i) => i.$3 == true).length;
                final allDone = completed == items.length;
                final firstIncomplete = items.firstWhere((i) => i.$3 != true, orElse: () => items.last);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          allDone ? 'All steps completed' : '${items.length - completed} steps remaining to start driving',
                          style: const TextStyle(color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final (_, label, done, action) = items[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: action == null ? null : () => action(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: done ? AppColors.success.withValues(alpha: 0.14) : AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      done ? Icons.check_rounded : Icons.description_outlined,
                                      size: 18,
                                      color: done ? AppColors.success : AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  Text(
                                    done ? 'Completed' : 'Required',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: done ? AppColors.success : AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PrimaryButton(
                          label: allDone ? 'Review & submit' : 'Upload documents',
                          onPressed: allDone
                              ? () => context.push('/d/onboarding/review')
                              : (firstIncomplete.$4 == null ? null : () => firstIncomplete.$4!()),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// "Choose an identity document" — Aadhaar or Other ID (PAN/Passport/DL).
/// The pick decides which upload screen comes next; there's no backend field
/// to distinguish the two, so it's purely which upload copy is shown.
class _IdentityChooserScreen extends StatelessWidget {
  const _IdentityChooserScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identity verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Identity verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Choose an identity document', style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 20),
          _ChoiceCard(
            icon: Icons.badge_rounded,
            title: 'Aadhaar',
            subtitle: 'Government identity',
            onTap: () => Navigator.pop(context, 'aadhaar'),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            icon: Icons.description_rounded,
            title: 'Other ID',
            subtitle: 'PAN / Passport / Driving Licence',
            onTap: () => Navigator.pop(context, 'other'),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
