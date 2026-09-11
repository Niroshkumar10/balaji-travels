import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../ride_request/where_to_screen.dart' show PlaceSearchSheet;

final _savedProvider = FutureProvider.autoDispose<List<SavedPlace>>((ref) async {
  final res = await ref.watch(miscRepoProvider).savedPlaces();
  return res.valueOrNull ?? [];
});

const _slots = [
  ('Home', Icons.home_rounded),
  ('Work', Icons.apartment_rounded),
  ('Others', Icons.place_rounded),
];

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  /// The most recently added saved place with this label (if the backend
  /// ends up holding more than one — see [_setSlot] — the newest wins).
  SavedPlace? _forSlot(List<SavedPlace> places, String label) {
    final matches = places.where((p) => p.label.toLowerCase() == label.toLowerCase()).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _setSlot(BuildContext context, WidgetRef ref, String label, SavedPlace? existing) async {
    final picked = await showModalBottomSheet<LatLngPoint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(title: 'Set $label address'),
    );
    if (picked == null) return;
    final repo = ref.read(miscRepoProvider);
    // No update endpoint — replace: add the new one, then drop the old.
    final res = await repo.addSavedPlace({
      'label': label,
      'lat': picked.lat,
      'lng': picked.lng,
      if (picked.addr != null) 'addr': picked.addr,
    });
    if (existing != null) await repo.removeSavedPlace(existing.id);
    res.when(
      ok: (_) => ref.invalidate(_savedProvider),
      err: (e) => context.mounted ? showError(context, e.message) : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_savedProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Favorites', fallbackRoute: '/c/home'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (places) {
          final others = places.where((p) => !_slots.any((s) => s.$1.toLowerCase() == p.label.toLowerCase())).toList();
          return ListView(
            children: [
              for (final slot in _slots) ...[
                Builder(builder: (context) {
                  final place = _forSlot(places, slot.$1);
                  return ListTile(
                    leading: Icon(slot.$2, color: AppColors.inkSoft),
                    title: Text(slot.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    subtitle: Text(
                      place?.addr ?? 'Tap to Add Address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: place == null ? AppColors.inkSoft : AppColors.textSecondary),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.inkSoft),
                      onPressed: () => _setSlot(context, ref, slot.$1, place),
                    ),
                    onTap: () => _setSlot(context, ref, slot.$1, place),
                  );
                }),
                const Divider(height: 1),
              ],
              if (others.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Other saved places', style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700)),
                ),
                ...others.map((p) => ListTile(
                      leading: const Icon(Icons.place_rounded, color: AppColors.inkSoft),
                      title: Text(p.label),
                      subtitle: Text(p.addr ?? '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          final res = await ref.read(miscRepoProvider).removeSavedPlace(p.id);
                          res.when(
                            ok: (_) => ref.invalidate(_savedProvider),
                            err: (e) => context.mounted ? showError(context, e.message) : null,
                          );
                        },
                      ),
                    )),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
