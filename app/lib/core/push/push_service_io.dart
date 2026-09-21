import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM + local notifications.
///
/// The backend sends DATA-ONLY messages (no `notification` block) so the
/// background handler always runs and we render our own notification — that's
/// what lets a killed driver app still surface a ride offer. If Firebase isn't
/// configured (`google-services.json` missing in dev), every method is a
/// silent no-op so the rest of the app is unaffected.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // Data-only: the OS won't auto-display it, so show a local notification.
  await PushService.instance._showLocal(message.data);
}

class PushService {
  PushService._();
  static final instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called with a fresh FCM token (on init and on refresh).
  void Function(String token)? onToken;

  /// Called when the user taps a notification (payload = the original FCM
  /// `data` map — type, rideId, etc.).
  void Function(Map<String, dynamic> data)? onTap;

  /// A tap that happened before [onTap] was wired up — e.g. the app was
  /// fully killed and got launched BY tapping a notification, which happens
  /// during [init] (called from main() before runApp()), long before
  /// anything has had a chance to set [onTap]. The caller should set
  /// [onTap] first, then call [deliverPendingTap] once (after the first
  /// frame, so navigation has somewhere to go).
  Map<String, dynamic>? _pendingTap;

  /// The token [init] already fetched before anything had wired up [onToken]
  /// — main() awaits init() fully, then runApp() constructs the widget tree
  /// that sets onToken, by which point init()'s own `onToken?.call(token)`
  /// already ran against a still-null callback and silently did nothing. Same
  /// shape as [_pendingTap]/[deliverPendingTap] below; deliver this once the
  /// caller has actually wired [onToken], or the very first token — the one
  /// that matters for a fresh install — is lost until the next unpredictable
  /// refresh, which in practice can be days or longer.
  String? _pendingToken;

  static const _channel = AndroidNotificationChannel(
    'rt_rides',
    'Ride updates',
    description: 'Ride requests, driver status and payment updates',
    importance: Importance.high,
  );

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase not configured — push disabled ($e)');
      return;
    }

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final data = _decode(r.payload);
        if (data != null) onTap?.call(data);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // The app was fully closed and got launched BY tapping a notification —
    // onDidReceiveNotificationResponse above never fires for this case, so
    // it has to be picked up here instead. onTap isn't wired yet this early
    // (init() runs in main(), before runApp()), so stash it for the caller
    // to deliver once it is — see deliverPendingTap().
    final launchDetails = await _local.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingTap = _decode(launchDetails!.notificationResponse?.payload);
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    FirebaseMessaging.onBackgroundMessage(_bgHandler);
    FirebaseMessaging.onMessage.listen((m) => _showLocal(m.data));
    // Data-only messages (see class doc) never carry the `notification`
    // block Android/iOS needs to route a tap here on their own — this fires
    // in practice only if that ever changes. Kept as a harmless extra path.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onTap?.call(m.data));

    final token = await messaging.getToken();
    if (token != null) {
      _pendingToken = token;
      onToken?.call(token);
    }
    messaging.onTokenRefresh.listen((t) {
      _pendingToken = t;
      onToken?.call(t);
    });

    _ready = true;
  }

  /// Call once, after wiring [onTap], to deliver a tap that launched the app
  /// from fully closed (missed above because [onTap] wasn't set yet).
  /// No-op if there wasn't one.
  void deliverPendingTap() {
    final data = _pendingTap;
    if (data == null) return;
    _pendingTap = null;
    onTap?.call(data);
  }

  /// Call once, after wiring [onToken], to deliver the token [init] already
  /// fetched before there was anywhere to send it. Safe to call
  /// unconditionally — no-op if there wasn't one. Deliberately does NOT clear
  /// [_pendingToken] (unlike [deliverPendingTap]'s one-shot tap): a login
  /// happening after this call still needs the same token to register it
  /// against the newly-authenticated user.
  void deliverPendingToken() {
    final token = _pendingToken;
    if (token == null) return;
    onToken?.call(token);
  }

  Map<String, dynamic>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? decoded.map((k, v) => MapEntry(k.toString(), v)) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showLocal(Map<String, dynamic> data) async {
    if (!_ready && !kReleaseMode) {
      // still try — init() may have partially run
    }
    final title = data['title']?.toString() ?? 'Sri Balaji Travels';
    final body = data['body']?.toString() ?? '';
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // The full data map round-trips through the payload so a tap can
      // route correctly (type + rideId, not just rideId) — see _decode.
      payload: jsonEncode(data),
    );
  }
}
