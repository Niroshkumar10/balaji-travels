/// No-op push service used on web (and any platform without dart:io).
class PushService {
  PushService._();
  static final instance = PushService._();

  void Function(String token)? onToken;
  void Function(Map<String, dynamic> data)? onTap;

  Future<void> init() async {
    // nothing: browsers in this test build don't receive FCM pushes
  }
}
