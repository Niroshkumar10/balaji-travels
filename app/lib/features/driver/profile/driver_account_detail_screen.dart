import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

/// One combined page for Personal information / Vehicle / Documents, each as
/// an expandable section — read-only summaries with an edit action inline,
/// rather than three separate bottom sheets. `initialExpanded` opens the
/// section the driver actually tapped into from the Account menu.
class DriverAccountDetailScreen extends ConsumerStatefulWidget {
  const DriverAccountDetailScreen({super.key, this.initialExpanded = 'personal'});
  final String initialExpanded;

  @override
  ConsumerState<DriverAccountDetailScreen> createState() => _DriverAccountDetailScreenState();
}

class _DriverAccountDetailScreenState extends ConsumerState<DriverAccountDetailScreen> {
  bool _busy = false;
  Set<String> _doneSteps = {};

  @override
  void initState() {
    super.initState();
    DriverOnboardingStore.doneSteps().then((s) {
      if (mounted) setState(() => _doneSteps = s);
    });
  }

  Future<void> _editPersonal(DriverProfile p) async {
    final name = TextEditingController(text: p.name ?? '');
    final email = TextEditingController(text: p.email ?? '');
    final license = TextEditingController(text: p.licenseNo ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit personal information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
            const SizedBox(height: 12),
            TextField(controller: license, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Driving licence number')),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateDriver({
      'name': name.text.trim(),
      if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
      if (license.text.trim().isNotEmpty) 'licenseNo': license.text.trim(),
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
                items: VehicleCategoryInfo.all.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}'))).toList(),
                onChanged: (v) => setLocal(() => cat = v ?? 'hatchback'),
              ),
              const SizedBox(height: 8),
              TextField(controller: plate, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Number plate')),
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
      appBar: const RtAppBar(title: 'Account details', fallbackRoute: '/d/profile'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (p) {
          if (p == null) return const EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable');
          return LoadingOverlay(
            busy: _busy,
            child: ListView(
              children: [
                ExpansionTile(
                  initiallyExpanded: widget.initialExpanded == 'personal',
                  title: const Text('Personal information', style: TextStyle(fontWeight: FontWeight.w700)),
                  leading: const Icon(Icons.person_rounded, color: AppColors.primary),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    InfoRow('Name', p.name?.isNotEmpty == true ? p.name! : '—'),
                    InfoRow('Phone', '+91 ${p.mobile}'),
                    InfoRow('Email', p.email?.isNotEmpty == true ? p.email! : '—'),
                    InfoRow('Licence no.', p.licenseNo?.isNotEmpty == true ? p.licenseNo! : '—'),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => _editPersonal(p), child: const Text('Edit')),
                  ],
                ),
                const Divider(height: 1),
                ExpansionTile(
                  initiallyExpanded: widget.initialExpanded == 'vehicle',
                  title: const Text('Vehicle', style: TextStyle(fontWeight: FontWeight.w700)),
                  leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.primary),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (p.vehicles.isEmpty) ...[
                      const Text('No vehicle added yet.', style: TextStyle(color: AppColors.inkSoft)),
                      const SizedBox(height: 12),
                      PrimaryButton(label: 'Add vehicle', onPressed: _addVehicle),
                    ] else
                      for (final v in p.vehicles) ...[
                        InfoRow('Category', VehicleCategoryInfo.of(v.category).name),
                        InfoRow('Plate', v.plateNo),
                        if (v.model?.isNotEmpty == true) InfoRow('Model', v.model!),
                        if (v.color?.isNotEmpty == true) InfoRow('Colour', v.color!),
                        InfoRow('Document status', v.docStatus),
                        const Divider(),
                      ],
                  ],
                ),
                const Divider(height: 1),
                ExpansionTile(
                  initiallyExpanded: widget.initialExpanded == 'documents',
                  title: const Text('Documents', style: TextStyle(fontWeight: FontWeight.w700)),
                  leading: const Icon(Icons.description_rounded, color: AppColors.primary),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _docRow('Driving licence', _doneSteps.contains('license')),
                    _docRow('Profile picture', _doneSteps.contains('photo')),
                    _docRow('Identity verification', _doneSteps.contains('identity')),
                    _docRow('Vehicle RC & paperwork', _doneSteps.contains('vehicle_rc')),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => context.push('/d/onboarding/checklist'),
                      child: const Text('Review documents'),
                    ),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _docRow(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: done ? AppColors.success : AppColors.inkSoft,
          ),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}
