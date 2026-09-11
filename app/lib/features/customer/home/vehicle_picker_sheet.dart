import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/vehicle_catalog.dart';

/// A finished pick from [showVehiclePickerSheet]: the group (e.g. "Tempo
/// Traveller") and the exact variant within it (e.g. "15-seater Tempo
/// Traveller").
class VehiclePick {
  const VehiclePick(this.category, this.variant);
  final String category;
  final String variant;

  String get label => '$category · $variant';
}

/// Two-step "what do you want to ride in" picker for Rental/Outstation trips:
/// a grid of vehicle-type boxes (Urbania / Tempo Traveller / Car / Bus),
/// then — once one is tapped — a list of that type's seater/model variants.
/// Returns the [VehiclePick], or null if the sheet was dismissed.
Future<VehiclePick?> showVehiclePickerSheet(BuildContext context) {
  return showModalBottomSheet<VehiclePick>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _VehiclePickerSheet(),
  );
}

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet();
  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  VehicleCategory? _selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  if (_selected != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => setState(() => _selected = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_selected != null) const SizedBox(width: 8),
                  Text(
                    _selected == null ? 'Choose a vehicle' : _selected!.label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _selected == null ? _typeGrid() : _variantList(_selected!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: VehicleCatalog.categories
          .map((c) => _TypeBox(category: c, onTap: () => setState(() => _selected = c)))
          .toList(),
    );
  }

  Widget _variantList(VehicleCategory category) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: category.variants.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final v = category.variants[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(category.icon, color: AppColors.primary),
            title: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            onTap: () => Navigator.pop(context, VehiclePick(category.label, v)),
          );
        },
      ),
    );
  }
}

class _TypeBox extends StatelessWidget {
  const _TypeBox({required this.category, required this.onTap});
  final VehicleCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(category.icon, size: 30, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(category.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
