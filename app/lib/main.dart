import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/session.dart';
import 'core/push/push_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
  }

  @override
  Widget build(BuildContext context) => const RedTaxiApp();
}
