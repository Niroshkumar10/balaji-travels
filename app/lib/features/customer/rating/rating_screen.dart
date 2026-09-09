import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _stars = 0;
  final _comment = TextEditingController();
  final _tags = <String>{};
  bool _busy = false;

  static const _tagOptions = [
    'Great driving',
    'Clean car',
    'Polite',
    'On time',
    'Good route',
    'Felt safe',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideSessionProvider.notifier).attach(widget.rideId);
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    final res = await ref.read(miscRepoProvider).rate(
          widget.rideId,
          stars: _stars,
          comment: _comment.text.trim(),
          tags: _tags.toList(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (_) {
        ref.read(rideSessionProvider.notifier).clear();
        context.go('/c/home');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(rideSessionProvider).ride;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate your ride'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () {
              ref.read(rideSessionProvider.notifier).clear();
              context.go('/c/home');
            },
            child: const Text('Skip'),
          ),
        ],
      ),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 34)),
            const SizedBox(height: 12),
            Center(
              child: Text(
                ride?.driver?.name ?? 'Your driver',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (ride?.finalFare != null)
              Center(
                child: Text('Paid ${money(ride!.finalFare)}',
                    style: const TextStyle(color: AppColors.inkSoft)),
              ),
            const SizedBox(height: 20),
            Center(
              child: RatingStars(
                value: _stars,
                size: 44,
                onChanged: (v) => setState(() => _stars = v),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tagOptions.map((t) {
                final on = _tags.contains(t);
                return FilterChip(
                  label: Text(t),
                  selected: on,
                  onSelected: (_) => setState(() => on ? _tags.remove(t) : _tags.add(t)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Submit',
              onPressed: _stars == 0 ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
