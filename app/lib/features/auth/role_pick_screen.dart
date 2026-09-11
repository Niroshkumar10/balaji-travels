import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_logo.dart';

class RolePickScreen extends StatelessWidget {
  const RolePickScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Positioned(left: 0, right: 0, bottom: 0, child: _BottomWave()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandLogo(stacked: true, iconSize: 44, fontSize: 26),
                  const SizedBox(height: 30),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                      children: const [
                        TextSpan(text: 'Welcome to\n', style: TextStyle(color: AppColors.textPrimary)),
                        TextSpan(text: 'Sri Balaji Travels', style: TextStyle(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your safe and reliable ride, always!',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 15),
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    icon: Icons.person_pin_circle_rounded,
                    title: 'Ride',
                    subtitle: 'Book a cab and track it live',
                    highlighted: true,
                    onTap: () => context.push('/c/onboarding/splash'),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    icon: Icons.directions_car_filled_rounded,
                    title: 'Drive',
                    subtitle: 'Accept rides and earn',
                    highlighted: false,
                    onTap: () => context.push('/d/onboarding/splash'),
                  ),
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'You can switch roles later from your profile.\nThe same number can be both.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0xFFFDECEA) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: highlighted ? null : Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Icon(icon, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft decorative band along the bottom of the splash — a light echo of the
/// skyline/road illustration in the reference design, built from shapes only
/// so it doesn't need a bundled image asset.
class _BottomWave extends StatelessWidget {
  const _BottomWave();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipPath(
        clipper: _WaveClipper(),
        child: Container(
          height: 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFCE4E1), Color(0xFFF6C6C0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.25, 0, size.width * 0.5, size.height * 0.25);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.5, size.width, size.height * 0.15);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
