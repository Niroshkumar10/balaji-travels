import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

const _faqs = [
  ('How is the fare calculated?',
      'The final fare is calculated by Sri Balaji Travels from the actual distance and time of your trip, plus any waiting charges. The estimate shown before booking may differ slightly.'),
  ('My driver cancelled — what now?',
      'You are not charged when a driver cancels. Just book again from the home screen.'),
  ('How do I get a receipt?',
      'Open the ride from "Bookings" and tap into it for the full fare breakdown.'),
  ('The OTP isn\'t working',
      'Make sure you are reading the OTP from the tracking screen, not an SMS. Ask the driver to re-enter it.'),
];

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _sections = [
    'My Account',
    'Safety',
    'Payment Methods',
    'Why Sri Balaji Travels?',
    'Booking a Ride',
    'Sri Balaji Travels App Setup',
    'Managing Your Ride',
    'Customer Support',
    "Booking Related FAQ's",
    "Payment Related FAQ's",
    "Safety Related FAQ's",
    "Ride Related FAQ's",
    "Support Related FAQ's",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RtAppBar(title: 'Help Center', fallbackRoute: '/c/home'),
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.canvas,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: const Text('FAQs', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          for (final s in _sections) ...[
            ListTile(
              title: Text(s, style: const TextStyle(fontSize: 15.5)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _HelpSectionScreen(title: s)),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// Content page for one Help Center row. "Customer Support" and "Booking
/// Related FAQ's" carry the real contact actions / FAQ answers this screen
/// used to show directly; the rest are placeholders — no real copy was
/// supplied for them yet, so this says so rather than inventing policy.
class _HelpSectionScreen extends StatelessWidget {
  const _HelpSectionScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RtAppBar(title: title, fallbackRoute: '/c/support'),
      body: switch (title) {
        'Customer Support' => _contactList(),
        "Booking Related FAQ's" => _faqList(),
        _ => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Content for this section is coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft),
              ),
            ),
          ),
      },
    );
  }

  Widget _contactList() {
    return ListView(
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
      ],
    );
  }

  Widget _faqList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _faqs
          .map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [Text(f.$2, style: const TextStyle(color: AppColors.inkSoft))],
                ),
              ))
          .toList(),
    );
  }
}
