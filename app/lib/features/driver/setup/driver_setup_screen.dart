import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

/// First-run setup: personal details + a vehicle. Also the place a driver lands
/// while KYC is pending.
class DriverSetupScreen extends ConsumerStatefulWidget {
  const DriverSetupScreen({super.key});
  @override
  ConsumerState<DriverSetupScreen> createState() => _State();
}

class _State extends ConsumerState<DriverSetupScreen> {
  final _name = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  String _category = 'hatchback';
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    for (final c in [_name, _license, _plate, _make, _model]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(DriverProfile p) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = p.name ?? '';
    _license.text = p.licenseNo ?? '';
  }

  Future<void> _save(DriverProfile p) async {
    setState(() => _busy = true);
    final repo = ref.read(profileRepoProvider);

    final upd = await repo.updateDriver({
      'name': _name.text.trim(),
      if (_license.text.trim().isNotEmpty) 'licenseNo': _license.text.trim(),
    });
    var err = upd.when(ok: (_) => null, err: (e) => e.message);

    if (err == null && p.vehicles.isEmpty && _plate.text.trim().isNotEmpty) {
      final v = await repo.addVehicle({
        'category': _category,
        'plateNo': _plate.text.trim(),
        if (_make.text.trim().isNotEmpty) 'make': _make.text.trim(),
        if (_model.text.trim().isNotEmpty) 'model': _model.text.trim(),
      });
      err = v.when(ok: (_) => null, err: (e) => e.message);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showError(context, err);
      return;
    }
    ref.invalidate(driverProfileProvider);
    ref.read(authControllerProvider.notifier).refreshName(_name.text.trim());
    context.go('/d/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Driver setup', fallbackRoute: '/d/dashboard'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (p) {
          if (p == null) {
            return const EmptyState(icon: Icons.person_off_rounded, title: 'Profile unavailable');
          }
          _hydrate(p);
          final hasVehicle = p.vehicles.isNotEmpty;
          return LoadingOverlay(
            busy: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (p.kycStatus == 'pending')
                  const _Banner(
                    color: AppColors.info,
                    icon: Icons.hourglass_bottom_rounded,
                    text: 'Your account is under review. You can add your details now — '
                        'you\'ll be able to go online once approved.',
                  ),
                if (p.kycStatus == 'rejected')
                  const _Banner(
                    color: AppColors.danger,
                    icon: Icons.error_rounded,
                    text: 'Your KYC was rejected. Please contact support.',
                  ),
                const SizedBox(height: 12),
                Text('Your details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 12),
                TextField(
                  controller: _license,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Driving licence number'),
                ),
                const SizedBox(height: 24),
                Text(hasVehicle ? 'Your vehicle' : 'Add a vehicle',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (hasVehicle)
                  Card(
                    child: ListTile(
                      leading: Text(
                        VehicleCategoryInfo.of(p.vehicles.first.category).emoji,
                        style: const TextStyle(fontSize: 26),
                      ),
                      title: Text(p.vehicles.first.label.isEmpty
                          ? VehicleCategoryInfo.of(p.vehicles.first.category).name
                          : p.vehicles.first.label),
                      subtitle: Text(p.vehicles.first.plateNo),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Vehicle type'),
                    items: VehicleCategoryInfo.all
                        .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji}  ${c.name}')))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v ?? 'hatchback'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Number plate', hintText: 'KA01AB1234'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _make,
                          decoration: const InputDecoration(labelText: 'Make'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _model,
                          decoration: const InputDecoration(labelText: 'Model'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                PrimaryButton(label: 'Save & continue', onPressed: () => _save(p)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
