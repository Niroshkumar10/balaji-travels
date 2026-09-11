import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_logo.dart';

/// First screen after tapping "Ride" or "Drive" on the role picker, shown
/// once before login. Purely a brand beat (auto-advances); the app's other
/// splash screen (features/splash) is the cold-boot auth check and is
/// unrelated to this one.
class RoleSplashScreen extends StatefulWidget {
  const RoleSplashScreen({super.key, required this.role});
  final AppRole role;

  @override
  State<RoleSplashScreen> createState() => _RoleSplashScreenState();
}

class _RoleSplashScreenState extends State<RoleSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) context.pushReplacement('/login', extra: widget.role);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.role == AppRole.driver;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(stacked: true, iconSize: 56, fontSize: 30),
            const SizedBox(height: 18),
            Container(width: 36, height: 3, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(
              isDriver ? 'Drive · Earn · Grow' : 'Ride · Relax · Reach',
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 36),
            const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}
