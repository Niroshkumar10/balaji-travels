import 'package:flutter/material.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';

/// Where earnings should be paid out — Bank Account or UPI. There is no
/// payout-details endpoint on the backend (payouts are handled by ops
/// manually today), so this is captured and saved locally only; it doesn't
/// yet reach a real payout pipeline.
class PaymentDetailsScreen extends StatefulWidget {
  const PaymentDetailsScreen({super.key});
  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  bool _bank = true;
  final _accountHolder = TextEditingController();
  final _accountNo = TextEditingController();
  final _ifsc = TextEditingController();
  final _upiId = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _accountHolder.dispose();
    _accountNo.dispose();
    _ifsc.dispose();
    _upiId.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_bank) {
      if (_accountHolder.text.trim().isEmpty || _accountNo.text.trim().isEmpty || _ifsc.text.trim().isEmpty) {
        showError(context, 'Fill in all bank details');
        return;
      }
    } else if (_upiId.text.trim().isEmpty) {
      showError(context, 'Enter your UPI ID');
      return;
    }
    setState(() => _busy = true);
    await DriverOnboardingStore.patch({
      'payoutMethod': _bank ? 'bank' : 'upi',
      if (_bank) ...{
        'bankAccountHolder': _accountHolder.text.trim(),
        'bankAccountNo': _accountNo.text.trim(),
        'bankIfsc': _ifsc.text.trim(),
      } else
        'upiId': _upiId.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment details')),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Where should we send your earnings?', style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _PayTab(label: 'Bank Account', selected: _bank, onTap: () => setState(() => _bank = true))),
                const SizedBox(width: 10),
                Expanded(child: _PayTab(label: 'UPI', selected: !_bank, onTap: () => setState(() => _bank = false))),
              ],
            ),
            const SizedBox(height: 20),
            if (_bank) ...[
              TextField(controller: _accountHolder, decoration: const InputDecoration(labelText: 'Account holder name')),
              const SizedBox(height: 14),
              TextField(
                controller: _accountNo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Account number'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ifsc,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'IFSC code'),
              ),
            ] else
              TextField(controller: _upiId, decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'yourname@upi')),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Verify account', onPressed: _verify),
          ],
        ),
      ),
    );
  }
}

class _PayTab extends StatelessWidget {
  const _PayTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : AppColors.cardSelectedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
        ),
        child: Text(label, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
