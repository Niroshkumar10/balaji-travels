import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

/// Registration number / model / colour / vehicle type / fuel type. All but
/// fuel type are real `rt_vehicles` columns and get saved for real via
/// ProfileRepository.addVehicle — there's no update-vehicle endpoint, so if
/// the driver already has a vehicle on file this just confirms it rather
/// than re-submitting. Fuel type has no backend column; kept locally.
class VehicleDetailsScreen extends ConsumerStatefulWidget {
  const VehicleDetailsScreen({super.key});
  @override
  ConsumerState<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends ConsumerState<VehicleDetailsScreen> {
  final _plate = TextEditingController();
  final _model = TextEditingController();
  String _category = 'hatchback';
  String _color = 'White';
  String _fuel = 'Petrol';
  bool _busy = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    super.dispose();
  }

  void _hydrate(DriverProfile p) {
    if (_hydrated) return;
    _hydrated = true;
    if (p.vehicles.isNotEmpty) {
      final v = p.vehicles.first;
      _plate.text = v.plateNo;
      _model.text = v.model ?? '';
      _category = v.category;
      _color = v.color?.isNotEmpty == true ? v.color! : _color;
    }
  }

  Future<void> _save(bool hasVehicle) async {
    if (_plate.text.trim().isEmpty) {
      showError(context, 'Enter the registration number');
      return;
    }
    setState(() => _busy = true);
    await DriverOnboardingStore.patch({'fuelType': _fuel});
    if (!hasVehicle) {
      final res = await ref.read(profileRepoProvider).addVehicle({
        'category': _category,
        'plateNo': _plate.text.trim(),
        'model': _model.text.trim(),
        'color': _color,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      res.when(
        ok: (_) {
          ref.invalidate(driverProfileProvider);
          Navigator.pop(context, true);
        },
        err: (e) => showError(context, e.message),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(driverProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Details')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (p) {
          final hasVehicle = p != null && p.vehicles.isNotEmpty;
          if (p != null) _hydrate(p);
          return LoadingOverlay(
            busy: _busy,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _plate,
                  enabled: !hasVehicle,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]'))],
                  decoration: const InputDecoration(labelText: 'Registration number', hintText: 'TN 38 XX 1234'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _model,
                  enabled: !hasVehicle,
                  decoration: const InputDecoration(labelText: 'Vehicle model', hintText: 'Honda Activa'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _color,
                  decoration: const InputDecoration(labelText: 'Colour'),
                  items: const ['White', 'Black', 'Silver', 'Red', 'Blue', 'Grey']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: hasVehicle ? null : (v) => setState(() => _color = v ?? _color),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Vehicle type'),
                  items: VehicleCategoryInfo.all
                      .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji}  ${c.name}')))
                      .toList(),
                  onChanged: hasVehicle ? null : (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _fuel,
                  decoration: const InputDecoration(labelText: 'Fuel type'),
                  items: const ['Petrol', 'Diesel', 'CNG', 'Electric']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => _fuel = v ?? _fuel),
                ),
                const SizedBox(height: 28),
                PrimaryButton(label: 'Continue', onPressed: () => _save(hasVehicle)),
              ],
            ),
          );
        },
      ),
    );
  }
}
