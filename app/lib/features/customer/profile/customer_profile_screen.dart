import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _profileProvider = FutureProvider.autoDispose<CustomerProfile?>((ref) async {
  final res = await ref.watch(profileRepoProvider).getCustomer();
  return res.when(ok: (p) => p, err: (e) => throw e);
});

class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});
  @override
  ConsumerState<CustomerProfileScreen> createState() => _State();
}

class _State extends ConsumerState<CustomerProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _payment = 'cash';
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _hydrate(CustomerProfile p) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = p.name ?? '';
    _email.text = p.email ?? '';
    _payment = p.defaultPaymentMethod;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateCustomer({
      'name': _name.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      'defaultPaymentMethod': _payment,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (p) {
        ref.read(authControllerProvider.notifier).refreshName(p.name ?? '');
        ref.invalidate(_profileProvider);
        showOk(context, 'Profile updated');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_profileProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Profile', fallbackRoute: '/c/home'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (p) {
          if (p == null) {
            return const EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable');
          }
          _hydrate(p);
          return LoadingOverlay(
            busy: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Column(
                    children: [
                      const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                      const SizedBox(height: 10),
                      Text('+91 ${p.mobile}', style: const TextStyle(color: AppColors.inkSoft)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                ),
                const SizedBox(height: 16),
                Text('Default payment', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments_rounded)),
                    ButtonSegment(value: 'upi', label: Text('UPI'), icon: Icon(Icons.qr_code_rounded)),
                  ],
                  selected: {_payment},
                  onSelectionChanged: (s) => setState(() => _payment = s.first),
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Save', onPressed: _save),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/role');
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
