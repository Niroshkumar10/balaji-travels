import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _faqs = [
    ('How is the fare calculated?',
        'The final fare is calculated by Sri Balaji Travels from the actual distance and time of your trip, plus any waiting charges. The estimate shown before booking may differ slightly.'),
    ('My driver cancelled — what now?',
        'You are not charged when a driver cancels. Just book again from the home screen.'),
    ('How do I get a receipt?',
        'Open the ride from "Your rides" and tap into it for the full fare breakdown.'),
    ('The OTP isn\'t working',
        'Make sure you are reading the 4-digit OTP from the tracking screen, not an SMS. Ask the driver to re-enter it.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RtAppBar(title: 'Support', fallbackRoute: '/c/home'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.call_rounded, color: AppColors.brand),
                  title: const Text('Call support'),
                  subtitle: const Text('24×7 helpline'),
                  onTap: () => launchUrl(Uri.parse('tel:18001234567')),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_rounded, color: AppColors.brand),
                  title: const Text('Email us'),
                  subtitle: const Text('support@sribalajitravels.example'),
                  onTap: () => launchUrl(Uri.parse('mailto:support@sribalajitravels.example')),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shield_rounded, color: AppColors.danger),
                  title: const Text('Safety / Emergency'),
                  subtitle: const Text('Contact local emergency services'),
                  onTap: () => launchUrl(Uri.parse('tel:112')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('FAQ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._faqs.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [Text(f.$2, style: const TextStyle(color: AppColors.inkSoft))],
                ),
              )),
        ],
      ),
    );
  }
}
