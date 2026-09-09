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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: RtAppBar(
        title: 'Profile',
        fallbackRoute: '/d/dashboard',
        showBack: widget.showBack,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Failure(
          message: '$e',
          onRetry: () => ref.invalidate(driverProfileProvider),
        ),
        data: (p) {
          if (p == null) {
            return _Failure(
              message: 'Could not load your profile.',
              onRetry: () => ref.invalidate(driverProfileProvider),
            );
          }
          _hydrate(p);
          final displayName = (p.name?.trim().isNotEmpty ?? false) ? p.name! : 'Driver';
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(driverProfileProvider.future),
            child: LoadingOverlay(
              busy: _busy,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                Center(
                  child: Column(
                    children: [
                      const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                      const SizedBox(height: 10),
                      Text(displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('+91 ${p.mobile}',
                          style: const TextStyle(color: AppColors.inkSoft)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                          Text(' ${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'),
                          const SizedBox(width: 10),
                          StatusPill(
                            'KYC ${p.kycStatus}',
                            color: p.kycApproved ? AppColors.success : AppColors.info,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
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
                  decoration: const InputDecoration(labelText: 'Driving licence number'),
                ),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Save', onPressed: _save),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('Vehicles', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addVehicle,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                ...p.vehicles.map((v) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(VehicleCategoryInfo.of(v.category).emoji,
                            style: const TextStyle(fontSize: 24)),
                        title: Text(v.label.isEmpty ? VehicleCategoryInfo.of(v.category).name : v.label),
                        subtitle: Text('${plate(v.plateNo)} · doc: ${v.docStatus}'),
                        trailing: v.isActive
                            ? const Chip(label: Text('Active'))
                            : null,
                      ),
                    )),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
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
                      const Icon(Icons.swap_horiz_rounded, color: AppColors.info),
                  title: const Text('Switch to Ride'),
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/role');
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/role');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_rounded, size: 52, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text('Profile unavailable',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
