import 'package:flutter/material.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import 'doc_capture_screen.dart';

/// Insurance policy number + expiry + the policy photo. No backend column
/// exists for any of this — the doc capture step doesn't persist the image
/// (see DriverOnboardingStore), and the policy number/expiry are saved
/// locally only, same as the rest of this device-only checklist.
class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});
  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  final _policyNo = TextEditingController();
  bool _uploaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _policyNo.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const DocCaptureScreen(
          title: 'Insurance',
          heading: 'Upload your vehicle insurance certificate',
          requirements: ['Valid insurance', 'Current policy number', 'Expiry date visible'],
          uploadLabel: 'Upload Insurance',
          dashedDropzone: true,
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
            const SizedBox(height: 20),
            TextField(controller: _policyNo, decoration: const InputDecoration(labelText: 'Policy number')),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Continue', onPressed: _continue),
          ],
        ),
      ),
    );
  }
}
