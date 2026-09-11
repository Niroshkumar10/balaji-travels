import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../core/store/profile_extras_store.dart';
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
  DateTime? _dob;
  String? _upi;
  bool _editing = false;
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _hydrate(CustomerProfile p) async {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = p.name ?? '';
    _email.text = p.email ?? '';
    final dobStr = await ProfileExtrasStore.dob();
    final upi = await ProfileExtrasStore.upi();
    if (!mounted) return;
    setState(() {
      if (dobStr != null) _dob = DateTime.tryParse(dobStr);
      _upi = upi;
    });
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateCustomer({
      'name': _name.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
    });
    if (_dob != null) await ProfileExtrasStore.setDob(_dob!.toIso8601String());
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (p) {
        ref.read(authControllerProvider.notifier).refreshName(p.name ?? '');
        ref.invalidate(_profileProvider);
        setState(() => _editing = false);
        showOk(context, 'Profile updated');
      },
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _editUpi() async {
    final current = await ProfileExtrasStore.upi();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('UPI ID'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'yourname@upi'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && ctrl.text.trim().isNotEmpty) {
      await ProfileExtrasStore.setUpi(ctrl.text.trim());
      if (mounted) setState(() => _upi = ctrl.text.trim());
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will sign you out. Account deletion isn\'t available in-app yet — contact support to fully erase your data.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/role');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_profileProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'My Profile', fallbackRoute: '/c/home'),
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
            child: Builder(
              builder: (context) {
                final upi = _upi;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(radius: 40, backgroundColor: AppColors.canvas, child: Icon(Icons.person, size: 40, color: AppColors.inkSoft)),
                        const Spacer(),
                        IconButton(
                          icon: Icon(_editing ? Icons.check_rounded : Icons.edit_rounded, color: AppColors.primary),
                          onPressed: _editing ? _save : () => setState(() => _editing = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _editing
                        ? TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Full name'),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          )
                        : Text(
                            _name.text.isNotEmpty ? _name.text : 'Add your name',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                    const SizedBox(height: 18),
                    _InfoRow(icon: Icons.call_rounded, value: '+91 ${p.mobile}'), // real, not editable — login identity
                    const SizedBox(height: 14),
                    _editing
                        ? TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined), hintText: 'Email'),
                          )
                        : _InfoRow(
                            icon: Icons.email_outlined,
                            value: _email.text.isNotEmpty ? _email.text : 'Add your email',
                          ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _editing ? _pickDob : null,
                      child: _InfoRow(
                        icon: Icons.cake_outlined,
                        value: _dob != null ? DateFormat('dd/MM/yyyy').format(_dob!) : 'Add your birthday',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_rounded, color: AppColors.inkSoft),
                      title: const Text('UPI', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(upi?.isNotEmpty == true ? upi! : 'Add your UPI ID', style: const TextStyle(color: AppColors.inkSoft)),
                      trailing: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.transparent,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                          onPressed: _editUpi,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    PrimaryButton(
                      label: 'Logout',
                      onPressed: () async {
                        await ref.read(authControllerProvider.notifier).logout();
                        if (context.mounted) context.go('/role');
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _confirmDelete,
                        child: const Text('Delete Account'),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.inkSoft),
        const SizedBox(width: 14),
        Text(value, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
      ],
    );
  }
}
