/// Push notifications entry point.
///
/// Native (Android/iOS) gets the real FCM + local-notification implementation;
/// web gets a no-op (flutter_local_notifications has no web support, and we
/// don't need background push in a browser test build). Conditional import
/// keeps the web bundle from ever loading the native-only packages.
library;

export 'push_service_stub.dart' if (dart.library.io) 'push_service_io.dart';
