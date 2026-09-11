import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/store/driver_onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';
import '../onboarding/payment_details_screen.dart';
import 'driver_account_detail_screen.dart';

const _languages = ['English', 'தமிழ் (Tamil)', 'తెలుగు (Telugu)', 'ಕನ್ನಡ (Kannada)', 'हिंदी (Hindi)'];

/// The "Account" screen — a menu of everything about the driver, matching
/// the reference: Personal information / Vehicle / Documents / Bank details
/// / Language / Notifications / Safety / Help & support, then Log out.
/// Personal information / Vehicle / Documents open the combined expandable
/// DriverAccountDetailScreen rather than three separate sheets.
class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, this.showBack = true});
  final bool showBack;
  @override
  ConsumerState<DriverProfileScreen> createState() => _State();
}

class _State extends ConsumerState<DriverProfileScreen> {
  void _openDetail(String section) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DriverAccountDetailScreen(initialExpanded: section)),
      );

  Future<void> _pickLanguage() async {
    final current = (await DriverOnboardingStore.get())['language'] as String?;
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _languages
              .map((l) => ListTile(
                    title: Text(l),
                    trailing: l == current ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () => Navigator.pop(context, l),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) await DriverOnboardingStore.patch({'language': picked});
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/role');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverProfileProvider);
    final auth = ref.watch(authControllerProvider);
    final p = async.valueOrNull;

    final name = (p?.name?.trim().isNotEmpty ?? false) ? p!.name!.trim() : (auth.name?.trim().isNotEmpty ?? false) ? auth.name!.trim() : 'Driver';
    final mobile = p?.mobile ?? auth.mobile ?? '';

    return Scaffold(
      appBar: RtAppBar(title: 'Account', fallbackRoute: '/d/dashboard', showBack: widget.showBack),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(driverProfileProvider.future),
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Center(
                child: Column(
                  children: [
                    const CircleAvatar(radius: 40, backgroundColor: AppColors.canvas, child: Icon(Icons.person, size: 40, color: AppColors.inkSoft)),
                    const SizedBox(height: 10),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    if (mobile.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('+91 $mobile', style: const TextStyle(color: AppColors.inkSoft)),
                    ],
                    if (p != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.accent, size: 18),
                          Text(' ${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (p == null)
                _DetailsUnavailable(loading: async.isLoading, onRetry: () => ref.invalidate(driverProfileProvider))
              else ...[
                const Divider(height: 1),
                AppTile(icon: Icons.person_rounded, title: 'Personal information', onTap: () => _openDetail('personal')),
                AppTile(icon: Icons.directions_car_filled_rounded, title: 'Vehicle', onTap: () => _openDetail('vehicle')),
                AppTile(icon: Icons.description_rounded, title: 'Documents', onTap: () => _openDetail('documents')),
                AppTile(
                  icon: Icons.account_balance_rounded,
                  title: 'Bank details',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentDetailsScreen())),
                ),
                AppTile(icon: Icons.language_rounded, title: 'Language', onTap: _pickLanguage),
                AppTile(icon: Icons.notifications_rounded, title: 'Notifications', onTap: () => context.push('/d/notifications')),
                AppTile(icon: Icons.shield_rounded, title: 'Safety', iconColor: AppColors.error, onTap: () => context.push('/d/safety')),
                AppTile(icon: Icons.help_outline_rounded, title: 'Help & support', onTap: () => context.push('/d/safety')),
                AppTile(icon: Icons.savings_rounded, title: 'Wallet & payouts', iconColor: AppColors.secondary, onTap: () => context.push('/d/wallet')),
                AppTile(icon: Icons.swap_horiz_rounded, title: 'Switch to Ride', iconColor: AppColors.info, onTap: _logout),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline placeholder for the menu block when `/drivers/me` hasn't loaded —
/// there's nothing to show a Personal information / Vehicle / etc. menu
/// against without it.
class _DetailsUnavailable extends StatelessWidget {
  const _DetailsUnavailable({required this.loading, required this.onRetry});
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
        child: Column(
          children: [
            if (loading)
              const CircularProgressIndicator()
            else ...[
              const Icon(Icons.cloud_off_rounded, color: AppColors.inkSoft),
              const SizedBox(height: 8),
              const Text("Couldn't load your details.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
