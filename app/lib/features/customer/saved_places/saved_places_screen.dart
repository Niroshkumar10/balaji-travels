import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';

final _savedProvider = FutureProvider.autoDispose<List<SavedPlace>>((ref) async {
  final res = await ref.watch(miscRepoProvider).savedPlaces();
  return res.valueOrNull ?? [];
});

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add saved place'),
        content: TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(hintText: 'Label (e.g. Gym)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Next')),
        ],
      ),
    );
    if (ok != true || labelCtrl.text.trim().isEmpty) return;

    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null) {
      if (context.mounted) showError(context, 'Could not get a location to save');
      return;
    }
    final res = await ref.read(miscRepoProvider).addSavedPlace({
      'label': labelCtrl.text.trim(),
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
    res.when(
      ok: (_) => ref.invalidate(_savedProvider),
      err: (e) => context.mounted ? showError(context, e.message) : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_savedProvider);
    return Scaffold(
      appBar: const RtAppBar(title: 'Saved places', fallbackRoute: '/c/home'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (places) {
          if (places.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No saved places',
              subtitle: 'Save your frequent spots for one-tap booking.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: places.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = places[i];
              return ListTile(
                leading: const Icon(Icons.place_rounded),
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
              );
            },
          );
        },
      ),
    );
  }
}
