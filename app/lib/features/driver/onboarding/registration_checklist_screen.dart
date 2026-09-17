import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import '../../../state/providers.dart';
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

  /// This is reached straight off the intro pages (a real push, so the
  /// default back button could pop back there) but also straight from a
  /// fresh app launch or the Application Status screen, with no earlier
  /// screen to pop to. Either way, "back" here means abandoning the whole
  /// driver sign-up, so it deliberately always lands on the Ride/Drive
  /// picker rather than depending on the Navigator stack — logging out
  /// first so the router's auth-redirect doesn't bounce it straight back.
  Future<void> _back() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/role');
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
    Future<bool> Function(Uint8List bytes)? onUsePhoto,
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
          onUsePhoto: onUsePhoto,
        ),
      ),
    );
    if (ok == true) await _markDone(step);
  }

  /// Uploads a driver document (license/id_proof/photo) and refreshes
  /// [driverProfileProvider] on success so the checklist/status screen picks
  /// up the new kyc_status='pending' immediately. Returns false (without
  /// popping the review screen) on failure so the rider can retry.
  Future<bool> _uploadDriverDoc(
    Uint8List bytes, {
    required String docType,
    String? idProofType,
  }) async {
    final res = await ref.read(profileRepoProvider).uploadDriverDocument(
          docType: docType,
          fileBytes: bytes,
          filename: '$docType.jpg',
          idProofType: idProofType,
        );
    return res.when(
      ok: (_) {
        ref.invalidate(driverProfileProvider);
        return true;
      },
      err: (e) {
        if (mounted) showError(context, e.message);
        return false;
      },
    );
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
      onUsePhoto: (bytes) => _uploadDriverDoc(
        bytes,
        docType: 'id_proof',
        idProofType: choice == 'aadhaar' ? 'aadhaar' : 'other',
      ),
    );
  }

  Future<void> _openVehicleSequence() async {
    // Vehicle details first — it's what actually creates the rt_vehicles
    // row (ProfileRepository.addVehicle). The RC upload has to come after:
    // the backend's uploadVehicleDocument requires a vehicle to already be
    // on file, and used to fail with "No vehicle on file for this driver
    // yet" because this screen order had the RC photo uploading before any
    // vehicle existed to attach it to.
    final detailsOk = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const VehicleDetailsScreen()));
    if (detailsOk != true || !mounted) return;

    final vehicleOk = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocCaptureScreen(
          title: 'Vehicle RC',
          heading: 'Upload your vehicle Registration Certificate',
          requirements: const ['Valid RC', 'Vehicle number visible'],
          uploadLabel: 'Upload RC',
          dashedDropzone: true,
          onUsePhoto: (bytes) async {
            final res = await ref.read(profileRepoProvider).uploadVehicleDocument(
                  docType: 'rc',
                  fileBytes: bytes,
                  filename: 'rc.jpg',
                );
            return res.when(
              ok: (_) {
                ref.invalidate(driverProfileProvider);
                return true;
              },
              err: (e) {
                if (mounted) showError(context, e.message);
                return false;
              },
            );
          },
        ),
      ),
    );
    if (vehicleOk != true || !mounted) return;

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
      appBar: RtAppBar(title: 'Complete your driver profile', onBack: _back),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
              data: (p) {
                final hasVehicle = p != null && p.vehicles.isNotEmpty;
                // A step counts as done if EITHER this device remembers doing
                // it (_done — the local checklist store) OR the backend
                // already has that document on file (a re-install, a new
                // device, or a document uploaded/approved through another
                // session all clear local storage without undoing real
                // progress) — local storage alone used to be the only signal,
                // which is what made an already-approved driver's checklist
                // look entirely incomplete after nothing more than a fresh
                // app install.
                final licenseDone = _done.contains('license') || p?.licenseDocPath != null;
                final photoDone = _done.contains('photo') || p?.photoPath != null;
                final identityDone = _done.contains('identity') || p?.idProofDocPath != null;
                final vehicleDone = hasVehicle &&
                    (_done.contains('vehicle_rc') || p.activeVehicle?.rcDocPath != null);
                final List<(String, String, bool, Future<void> Function()?)> items = [
                  ('profile', 'Personal information', p?.name?.isNotEmpty == true, null),
                  ('license', 'Driving Licence', licenseDone, () => _openDoc(
                        'license',
                        title: 'Driving Licence',
                        description: "We need your valid driving licence to verify that you're eligible to drive.",
                        requirements: const ['Valid licence', 'Name should match your profile', 'Clear photo', 'All details must be readable'],
                        uploadLabel: 'Upload Licence',
                        onUsePhoto: (bytes) => _uploadDriverDoc(bytes, docType: 'license'),
                      )),
                  ('photo', 'Profile picture', photoDone, () => _openDoc(
                        'photo',
                        title: 'Add a profile photo',
                        heading: 'Add a profile photo',
                        description: 'Your photo will be shown to customers when you receive a ride.',
                        requirements: const ['Face clearly visible', 'No sunglasses', 'Good lighting', 'No group photo'],
                        uploadLabel: 'Take Photo',
                        circular: true,
                        primaryOpensCamera: true,
                        onUsePhoto: (bytes) => _uploadDriverDoc(bytes, docType: 'photo'),
                      )),
                  ('identity', 'Identity verification', identityDone, _openIdentity),
                  ('vehicle_rc', 'Vehicle RC', vehicleDone, _openVehicleSequence),
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
