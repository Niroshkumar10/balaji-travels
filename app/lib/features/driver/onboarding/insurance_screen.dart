import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';
import 'doc_capture_screen.dart';

/// Insurance policy number + expiry + the policy photo. The photo + policy
/// number/expiry now upload to rt_vehicles (insurance_number/expiry/doc_path
/// — see vehicle_driver_documents.sql), same as the RC step in the checklist;
/// the local DriverOnboardingStore copy is kept too only so the checklist's
/// own "done" tracking (a device-only concept, unrelated to KYC) still works.
class InsuranceScreen extends ConsumerStatefulWidget {
  const InsuranceScreen({super.key});
  @override
  ConsumerState<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends ConsumerState<InsuranceScreen> {
  final _policyNo = TextEditingController();
  DateTime? _expiry;
  bool _uploaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _policyNo.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _upload() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocCaptureScreen(
          title: 'Insurance',
          heading: 'Upload your vehicle insurance certificate',
          requirements: const ['Valid insurance', 'Current policy number', 'Expiry date visible'],
          uploadLabel: 'Upload Insurance',
          dashedDropzone: true,
          onUsePhoto: (bytes) async {
            final res = await ref.read(profileRepoProvider).uploadVehicleDocument(
                  docType: 'insurance',
                  fileBytes: bytes,
                  filename: 'insurance.jpg',
                  number: _policyNo.text.trim().isEmpty ? null : _policyNo.text.trim(),
                  expiry: _expiry,
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
    if (ok == true) setState(() => _uploaded = true);
  }

  Future<void> _continue() async {
    if (!_uploaded) {
      showError(context, 'Upload your insurance document first');
      return;
    }
    setState(() => _busy = true);
    await DriverOnboardingStore.patch({'insurancePolicyNo': _policyNo.text.trim()});
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insurance')),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Upload your vehicle insurance certificate.', style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            TextField(controller: _policyNo, decoration: const InputDecoration(labelText: 'Policy number')),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickExpiry,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry date'),
                child: Text(
                  _expiry == null
                      ? 'Select date'
                      : '${_expiry!.day}/${_expiry!.month}/${_expiry!.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _upload,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _uploaded ? AppColors.success : AppColors.line),
                ),
                child: Column(
                  children: [
                    Icon(
                      _uploaded ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                      size: 40,
                      color: _uploaded ? AppColors.success : AppColors.inkSoft,
                    ),
                    const SizedBox(height: 10),
                    Text(_uploaded ? 'Insurance document added' : 'Take photo or choose from gallery'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Continue', onPressed: _continue),
          ],
        ),
      ),
    );
  }
}
