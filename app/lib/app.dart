import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'router.dart';

class RedTaxiApp extends ConsumerWidget {
  const RedTaxiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sri Balaji Travels',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark theme is fully built; switch to ThemeMode.system (or wire a
      // user toggle) to enable it — no redesign needed.
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
