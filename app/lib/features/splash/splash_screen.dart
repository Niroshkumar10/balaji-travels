import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_colors.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final st = ref.read(authControllerProvider);
    final session = ref.read(sessionProvider);

    if (st.status == AuthStatus.authenticated) {
      context.go(st.role == AppRole.driver ? '/d/dashboard' : '/c/home');
    } else if (!session.onboarded) {
      context.go('/onboarding');
    } else {
      context.go('/role');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.brand,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.temple_hindu_rounded, size: 68, color: AppColors.accent),
            SizedBox(height: 18),
            Text(
              'Sri Balaji Travels',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'BOOK A RIDE',
              style: TextStyle(color: AppColors.accentBright, fontSize: 12, letterSpacing: 3),
            ),
            SizedBox(height: 26),
            SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
