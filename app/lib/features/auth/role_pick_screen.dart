import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';

class RolePickScreen extends StatelessWidget {
  const RolePickScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.local_taxi_rounded, size: 56, color: AppColors.brand),
              const SizedBox(height: 16),
              Text('Welcome to Sri Balaji Travels', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('How do you want to use the app?',
                  style: TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 32),
              _RoleCard(
                icon: Icons.person_pin_circle_rounded,
                title: 'Ride',
                subtitle: 'Book a cab and track it live',
                onTap: () => context.push('/login', extra: AppRole.customer),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.directions_car_filled_rounded,
                title: 'Drive',
                subtitle: 'Accept rides and earn',
                onTap: () => context.push('/login', extra: AppRole.driver),
              ),
              const Spacer(),
              const Text(
                'You can switch roles later from your profile. The same number can be both.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.brand.withValues(alpha: 0.1),
                child: Icon(icon, color: AppColors.brand),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
