import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

/// The Profile TAB — a simple, editable "My Profile" view matching the
/// rider's own profile screen: name/email are real backend fields (saved via
/// ProfileRepository.updateDriver), phone is the real, non-editable login
/// identity, and address/UPI have no backend column yet so they're kept in
/// DriverOnboardingStore (the same local-only store the onboarding wizard's
/// Payment Details step already uses for UPI) — clearly local, not a fake
/// server round-trip. Everything else about the driver's account (vehicle,
/// documents, bank details, language, safety, wallet…) now lives in the
/// hamburger drawer on the Home tab instead of here.
class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, this.showBack = true, this.onBack});
  final bool showBack;

  /// When this screen is a bottom-nav tab rather than a pushed route, pass a
  /// callback that switches the shell back to Home instead of trying to pop.
  final VoidCallback? onBack;
  @override
  ConsumerState<DriverProfileScreen> createState() => _State();
}

class _State extends ConsumerState<DriverProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _address;
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

  Future<void> _hydrate(String? name, String? email) async {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = name ?? '';
    _email.text = email ?? '';
    final local = await DriverOnboardingStore.get();
    if (!mounted) return;
    setState(() {
      _address = local['address'] as String?;
      _upi = local['upiId'] as String?;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateDriver({
      'name': _name.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (p) {
        ref.read(authControllerProvider.notifier).refreshName(p.name ?? '');
        ref.invalidate(driverProfileProvider);
        setState(() => _editing = false);
        showOk(context, 'Profile updated');
      },
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _editAddress() async {
    final ctrl = TextEditingController(text: _address ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Address'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Your address'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && ctrl.text.trim().isNotEmpty) {
      await DriverOnboardingStore.patch({'address': ctrl.text.trim()});
      if (mounted) setState(() => _address = ctrl.text.trim());
    }
  }

  Future<void> _editUpi() async {
    final ctrl = TextEditingController(text: _upi ?? '');
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
      await DriverOnboardingStore.patch({'upiId': ctrl.text.trim(), 'payoutMethod': 'upi'});
      if (mounted) setState(() => _upi = ctrl.text.trim());
    }
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/role');
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
    await _logout();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverProfileProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: RtAppBar(title: 'My Profile', fallbackRoute: '/d/dashboard', showBack: widget.showBack, onBack: widget.onBack),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (p) {
          if (p == null) {
            return const EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable');
          }
          final mobile = p.mobile.isNotEmpty ? p.mobile : (auth.mobile ?? '');
          _hydrate(p.name, p.email);
          return LoadingOverlay(
            busy: _busy,
            child: Builder(
              builder: (context) {
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
                    if (mobile.isNotEmpty) _InfoRow(icon: Icons.call_rounded, value: '+91 $mobile'), // real, not editable — login identity
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
                      onTap: _editAddress,
                      child: _InfoRow(
                        icon: Icons.home_outlined,
                        value: (_address?.isNotEmpty ?? false) ? _address! : 'Add your address',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_rounded, color: AppColors.inkSoft),
                      title: const Text('UPI', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text((_upi?.isNotEmpty ?? false) ? _upi! : 'Add your UPI ID', style: const TextStyle(color: AppColors.inkSoft)),
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
                    PrimaryButton(label: 'Logout', onPressed: _logout),
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
        Expanded(child: Text(value, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary))),
      ],
    );
  }
}
