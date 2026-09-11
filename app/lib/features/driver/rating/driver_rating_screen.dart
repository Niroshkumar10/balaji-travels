import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';

const _tags = ['Customer was polite', 'Easy pickup', 'Difficult pickup', 'Other'];

/// Driver rates the customer after a completed trip — the same
/// `/ratings/rides/:id` endpoint the customer-side rating screen uses; the
/// backend attributes it correctly from the driver's own auth role, so this
/// is a real rating, not a cosmetic one.
class DriverRatingScreen extends ConsumerStatefulWidget {
  const DriverRatingScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends ConsumerState<DriverRatingScreen> {
  int _stars = 5;
  final Set<String> _selectedTags = {};
  bool _busy = false;

  void _done() {
    ref.read(driverControllerProvider.notifier).clearFinishedRide();
    context.go('/d/dashboard');
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await ref.read(miscRepoProvider).rate(
          widget.rideId,
          stars: _stars,
          tags: _selectedTags.toList(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) => _done(),
      err: (e) {
        // Already-rated / ride-not-completed are non-fatal here — either way
        // there's nothing left to submit, so just move on.
        _done();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadingOverlay(
          busy: _busy,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                const Text('How was your experience?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _stars;
                    return IconButton(
                      iconSize: 36,
                      onPressed: () => setState(() => _stars = i + 1),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: filled ? AppColors.secondary : AppColors.inkSoft,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: _tags.map((t) {
                    final selected = _selectedTags.contains(t);
                    return FilterChip(
                      label: Text(t),
                      selected: selected,
                      onSelected: (v) => setState(() => v ? _selectedTags.add(t) : _selectedTags.remove(t)),
                      selectedColor: AppColors.cardSelectedBackground,
                      checkmarkColor: AppColors.primary,
                    );
                  }).toList(),
                ),
                const Spacer(),
                PrimaryButton(label: 'Submit', onPressed: _submit),
                const SizedBox(height: 8),
                TextButton(onPressed: _done, child: const Text('Skip')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
