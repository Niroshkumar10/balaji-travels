import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

const _services = [
  ('local', 'Local rides', 'Point-to-point rides within the city', Icons.location_city_rounded),
  ('rental', 'Rentals', 'Hourly/package bookings (e.g. 4hr/40km)', Icons.schedule_rounded),
  ('outstation', 'Outstation trips', 'One-way or round trips between cities', Icons.alt_route_rounded),
];

/// Which bookings this driver receives — matches rt_drivers.service_types.
/// Set during onboarding, editable any time from here. At least one must
/// stay on: a driver with none would never be offered a ride.
class TripPreferencesScreen extends ConsumerStatefulWidget {
  const TripPreferencesScreen({super.key});
  @override
  ConsumerState<TripPreferencesScreen> createState() => _TripPreferencesScreenState();
}

class _TripPreferencesScreenState extends ConsumerState<TripPreferencesScreen> {
  Set<String>? _selected;
  bool _busy = false;

  Set<String> _selectedOrInit(BuildContext context) {
    if (_selected != null) return _selected!;
    final p = ref.read(driverProfileProvider).valueOrNull;
    return _selected = {...(p?.serviceTypes ?? const ['local'])};
  }

  Future<void> _save() async {
    final sel = _selected;
    if (sel == null || sel.isEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(profileRepoProvider).updateDriver({'serviceTypes': sel.toList()});
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.invalidate(driverProfileProvider);
        Navigator.pop(context);
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOrInit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Trip preferences')),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Choose which bookings you want to receive. You can change this any time.',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 20),
            ..._services.map((s) {
              final on = selected.contains(s.$1);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() {
                    on ? selected.remove(s.$1) : selected.add(s.$1);
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? AppColors.primary : AppColors.line, width: on ? 2 : 1),
                      color: on ? AppColors.cardSelectedBackground : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(s.$4, color: AppColors.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text(s.$3, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Switch(value: on, onChanged: (_) => setState(() {
                          on ? selected.remove(s.$1) : selected.add(s.$1);
                        })),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save', onPressed: selected.isEmpty ? null : _save),
          ],
        ),
      ),
    );
  }
}
