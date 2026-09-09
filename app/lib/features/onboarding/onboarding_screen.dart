import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _slides = [
    (Icons.pin_drop_rounded, 'Book in seconds', 'Set your pickup and destination, see the fare up front.'),
    (Icons.directions_car_filled_rounded, 'Track live', 'Watch your driver approach on the map with a real ETA.'),
    (Icons.verified_user_rounded, 'Pay your way', 'Cash or UPI — the final fare is calculated fairly by the system.'),
  ];

  Future<void> _finish() async {
    await ref.read(sessionProvider).setOnboarded();
    if (mounted) context.go('/role');
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s.$1, size: 96, color: AppColors.brand),
                        const SizedBox(height: 32),
                        Text(s.$2, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(
                          s.$3,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SmoothPageIndicator(
              controller: _pc,
              count: _slides.length,
              effect: const ExpandingDotsEffect(
                activeDotColor: AppColors.brand,
                dotHeight: 8,
                dotWidth: 8,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: PrimaryButton(
                label: _page == _slides.length - 1 ? 'Get started' : 'Next',
                onPressed: () {
                  if (_page == _slides.length - 1) {
                    _finish();
                  } else {
                    _pc.nextPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
