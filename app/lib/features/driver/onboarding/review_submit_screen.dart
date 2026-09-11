import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';

/// Summary of everything the checklist collected, with a submit action that
/// marks the local application "submitted" and hands off to a real
/// Application Submitted screen, then the verification-status screen —
/// which reflects the real, backend `kycStatus` (an ops reviewer
/// approves/rejects it; this app can't).
class ReviewSubmitScreen extends ConsumerStatefulWidget {
  const ReviewSubmitScreen({super.key});
  @override
  ConsumerState<ReviewSubmitScreen> createState() => _ReviewSubmitScreenState();
}

class _ReviewSubmitScreenState extends ConsumerState<ReviewSubmitScreen> {
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    final id = ref.read(driverProfileProvider).valueOrNull?.id ?? DateTime.now().millisecondsSinceEpoch % 100000;
    final appId = 'SBTR${id.toString().padLeft(5, '0')}';
    await DriverOnboardingStore.patch({'submitted': true, 'applicationId': appId});
    if (!mounted) return;
    setState(() => _busy = false);
    context.pushReplacement('/d/onboarding/submitted', extra: appId);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(driverProfileProvider).valueOrNull;
    final vehicle = p?.vehicles.isNotEmpty == true ? p!.vehicles.first : null;
    final dob = DriverOnboardingStore.get();

    return Scaffold(
      appBar: AppBar(title: const Text('Review your information')),
      body: LoadingOverlay(
        busy: _busy,
        child: FutureBuilder<Map<String, dynamic>>(
          future: dob,
          builder: (context, snap) {
            final local = snap.data ?? const {};
            final dobStr = local['dob'] as String?;
            final dobLabel = dobStr != null ? DateFormat('d MMM yyyy').format(DateTime.parse(dobStr)) : null;
            final payoutMethod = local['payoutMethod'] as String?;
            final acctNo = local['bankAccountNo'] as String?;
            final upi = local['upiId'] as String?;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Section(
                  title: 'Personal',
                  onEdit: () => context.pop(),
                  lines: [
                    'Name · ${p?.name ?? '—'}',
                    'Phone · +91 ${p?.mobile ?? '—'}',
                    if (dobLabel != null) 'DOB · $dobLabel',
                  ],
                ),
                _Section(
                  title: 'Vehicle',
                  onEdit: () => context.pop(),
                  lines: [
                    'Model · ${vehicle == null ? '—' : (vehicle.label.isEmpty ? vehicle.category : vehicle.label)}',
                    if (vehicle != null) 'Reg No. · ${vehicle.plateNo}',
                  ],
                ),
                _Section(
                  title: 'Documents',
                  onEdit: () => context.pop(),
                  lines: const ['Driving Licence', 'Identity document', 'Vehicle RC', 'Insurance'],
                ),
                _Section(
                  title: 'Payment',
                  onEdit: () => context.pop(),
                  lines: [
                    payoutMethod == 'upi'
                        ? 'UPI · ${upi ?? '—'}'
                        : 'Bank Account · ${acctNo != null && acctNo.length > 4 ? '•••• ${acctNo.substring(acctNo.length - 4)}' : '—'}',
                  ],
                ),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Submit application', onPressed: _submit),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.lines, required this.onEdit});
  final String title;
  final List<String> lines;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              GestureDetector(
                onTap: onEdit,
                child: const Text('Edit', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l, style: const TextStyle(fontSize: 13.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
