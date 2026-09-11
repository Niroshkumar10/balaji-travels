import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

/// Shared by the "Safety" and "Help & support" menu items — same real
/// contact actions the customer-side Help Center uses (tel:/mailto: links),
/// reskinned for the driver account.
class DriverSafetyHelpScreen extends StatelessWidget {
  const DriverSafetyHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RtAppBar(title: 'Safety & Help', fallbackRoute: '/d/profile'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFDECEA),
            child: ListTile(
              leading: const Icon(Icons.shield_rounded, color: AppColors.error),
              title: const Text('Emergency', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Contact local emergency services'),
              onTap: () => launchUrl(Uri.parse('tel:112')),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.call_rounded, color: AppColors.brand),
                  title: const Text('Call support'),
                  subtitle: const Text('24×7 driver helpline'),
                  onTap: () => launchUrl(Uri.parse('tel:18001234567')),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_rounded, color: AppColors.brand),
                  title: const Text('Email us'),
                  subtitle: const Text('drivers@sribalajitravels.example'),
                  onTap: () => launchUrl(Uri.parse('mailto:drivers@sribalajitravels.example')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Safety tips', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const _TipRow(text: 'Verify the OTP before you start every trip.'),
          const _TipRow(text: 'Take breaks — fatigue is a leading cause of accidents.'),
          const _TipRow(text: 'Keep your documents and vehicle insurance up to date.'),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}
