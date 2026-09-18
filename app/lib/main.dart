import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/session.dart';
import 'core/push/push_navigation.dart';
import 'core/push/push_service.dart';
import 'core/widgets/map_markers.dart';
import 'router.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pre-render the custom map marker bitmaps so the first map that needs them
  // (home / tracking) already has them cached. Non-fatal if it fails.
  unawaited(MapMarkers.instance.ensureBuilt());

  final session = await Session.load();

  // Push (FCM + local notifications) — non-fatal if Firebase isn't configured.
  await PushService.instance.init();

  runApp(
    ProviderScope(
      overrides: [sessionProvider.overrideWithValue(session)],
      child: const _Boot(),
    ),
  );
}

/// Wires the FCM token → backend once the user is authenticated.
class _Boot extends ConsumerStatefulWidget {
  const _Boot();
  @override
  ConsumerState<_Boot> createState() => _BootState();
}

class _BootState extends ConsumerState<_Boot> {
  @override
  void initState() {
    super.initState();
    PushService.instance.onToken = (token) async {
      try {
        await ref.read(authRepoProvider).registerFcmToken(token);
      } catch (_) {/* will retry on next token refresh / login */}
    };
    PushService.instance.onTap = _handleNotificationTap;
    // Delivers a tap that launched the app from fully closed, if there was
    // one — safe to call unconditionally, it's a no-op otherwise.
    PushService.instance.deliverPendingTap();
    // PushService.init() (called in main(), before this widget existed to
    // set onToken above) already fetched the device's token and tried to
    // deliver it against a still-null onToken — silently a no-op. Without
    // this, an already-logged-in device would never register a token until
    // Firebase happened to rotate it, which is unpredictable and can be a
    // very long time. Safe to call unconditionally — a no-op if unauthenticated
    // (registerFcmToken 401s, caught above) or if there's no token yet.
    if (ref.read(sessionProvider).isAuthenticated) {
      PushService.instance.deliverPendingToken();
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final path = routeForNotification(data, ref.read(sessionProvider).role);
    if (path == null) return;
    // Deferred to after the current frame so this is safe to call from
    // initState (router/navigator may not be mounted yet) as well as from a
    // tap that arrives while the app is already running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routerProvider).push(path);
    });
  }

  @override
  Widget build(BuildContext context) => const RedTaxiApp();
}
