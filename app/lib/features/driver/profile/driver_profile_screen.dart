import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, this.showBack = true});
  final bool showBack;
  @override
  ConsumerState<DriverProfileScreen> createState() => _State();
}

class _State extends ConsumerState<DriverProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _license = TextEditingController();
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _license]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(DriverProfile p) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = p.name ?? '';
    _email.text = p.email ?? '';
    _license.text = p.licenseNo ?? '';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateDriver({
      'name': _name.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_license.text.trim().isNotEmpty) 'licenseNo': _license.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (p) {
        ref.read(authControllerProvider.notifier).refreshName(p.name ?? '');
        ref.invalidate(driverProfileProvider);
        showOk(context, 'Profile updated');
      },
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _addVehicle() async {
    final plate = TextEditingController();
    final make = TextEditingController();
    var cat = 'hatchback';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: cat,
                items: VehicleCategoryInfo.all
                    .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}')))
                    .toList(),
                onChanged: (v) => setLocal(() => cat = v ?? 'hatchback'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Number plate'),
              ),
              TextField(controller: make, decoration: const InputDecoration(labelText: 'Make/model')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || plate.text.trim().isEmpty) return;
    final res = await ref.read(profileRepoProvider).addVehicle({
      'category': cat,
      'plateNo': plate.text.trim(),
      if (make.text.trim().isNotEmpty) 'make': make.text.trim(),
    });
    if (!mounted) return;
    res.when(
      ok: (_) => ref.invalidate(driverProfileProvider),
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/role');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverProfileProvider);
    final auth = ref.watch(authControllerProvider);
    final p = async.valueOrNull;
    if (p != null) _hydrate(p);

    final name = (p?.name?.trim().isNotEmpty ?? false)
        ? p!.name!.trim()
        : (auth.name?.trim().isNotEmpty ?? false)
            ? auth.name!.trim()
            : 'Driver';
    final mobile = p?.mobile ?? auth.mobile ?? '';

    return Scaffold(
      appBar: RtAppBar(
        title: 'Profile',
        fallbackRoute: '/d/dashboard',
        showBack: widget.showBack,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(driverProfileProvider.future),
        child: LoadingOverlay(
          busy: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── header (always shown, from profile or auth) ──
              Center(
                child: Column(
                  children: [
                    const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                    const SizedBox(height: 10),
                    Text(name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (mobile.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('+91 $mobile',
                          style: const TextStyle(color: AppColors.inkSoft)),
                    ],
                    if (p != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: AppColors.accent, size: 18),
                          Text(' ${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'),
                          const SizedBox(width: 10),
                          StatusPill(
                            'KYC ${p.kycStatus}',
                            color: p.kycApproved
                                ? AppColors.success
                                : AppColors.info,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── editable details + vehicles (needs the fetch) ──
              if (p == null)
                _DetailsUnavailable(
                  loading: async.isLoading,
                  onRetry: () => ref.invalidate(driverProfileProvider),
                )
              else ...[
                const SectionHeader('Your details'),
                TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _license,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Driving licence number'),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Save', onPressed: _save),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('Vehicles',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addVehicle,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (p.vehicles.isEmpty)
                  const Text('No vehicle added yet.',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                ...p.vehicles.map((v) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(VehicleCategoryInfo.of(v.category).emoji,
                            style: const TextStyle(fontSize: 24)),
                        title: Text(v.label.isEmpty
                            ? VehicleCategoryInfo.of(v.category).name
                            : v.label),
                        subtitle: Text('${plate(v.plateNo)} · doc: ${v.docStatus}'),
                        trailing: v.isActive
                            ? const Chip(label: Text('Active'))
                            : null,
                      ),
                    )),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // ── account (always available, even if the profile failed) ──
              const SectionHeader('Account'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_rounded,
                    color: AppColors.primary),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/d/notifications'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.savings_rounded, color: AppColors.secondary),
                title: const Text('Wallet & payouts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/d/wallet'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.swap_horiz_rounded, color: AppColors.info),
                title: const Text('Switch to Ride'),
                onTap: _logout,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline placeholder for the details/vehicles block when `/drivers/me` hasn't
/// loaded — the account actions above stay usable regardless.
class _DetailsUnavailable extends StatelessWidget {
  const _DetailsUnavailable({required this.loading, required this.onRetry});
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          if (loading)
            const CircularProgressIndicator()
          else ...[
            const Icon(Icons.cloud_off_rounded, color: AppColors.inkSoft),
            const SizedBox(height: 8),
            const Text("Couldn't load your details and vehicles.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
