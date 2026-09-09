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

  /// Called when the user taps a notification (payload = message.data).
  void Function(Map<String, dynamic> data)? onTap;

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
        final payload = r.payload;
        if (payload != null) onTap?.call({'raw': payload});
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    FirebaseMessaging.onBackgroundMessage(_bgHandler);
    FirebaseMessaging.onMessage.listen((m) => _showLocal(m.data));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onTap?.call(m.data));

    final token = await messaging.getToken();
    if (token != null) onToken?.call(token);
    messaging.onTokenRefresh.listen((t) => onToken?.call(t));

    _ready = true;
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
      payload: data['rideId']?.toString(),
    );
  }
}
