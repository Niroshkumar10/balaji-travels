/// Runtime configuration — everything from `--dart-define`, nothing hard-coded.
///
/// The Microlab app hard-coded its Maps key and server URL in source; this
/// deliberately does not. Example run:
///
///   flutter run \
///     --dart-define=RT_API_BASE_URL=http://10.0.2.2:4000 \
///     --dart-define=RT_SOCKET_URL=http://10.0.2.2:4000
class AppConfig {
  const AppConfig._();

  /// Backend host WITHOUT the `/api/v1` suffix (ApiClient appends it).
  /// Default targets a backend on the same machine (works for `-d chrome` and
  /// desktop). For the ANDROID EMULATOR pass
  /// `--dart-define=RT_API_BASE_URL=http://10.0.2.2:4000`; for a physical
  /// device use your machine's LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'RT_API_BASE_URL',
    // defaultValue: 'http://localhost:4000',
    defaultValue: 'https://chat.neuralarc.com',
  );

  static const String socketUrl = String.fromEnvironment(
    'RT_SOCKET_URL',
    // defaultValue: 'http://localhost:4000',
    defaultValue: 'https://chat.neuralarc.com',
  );

  /// Only needed if the app calls Google Places directly. The default path
  /// proxies geocoding through the backend, so this normally stays empty.
  static const String mapsApiKey =
      String.fromEnvironment('RT_MAPS_API_KEY', defaultValue: '');

  static const String flavor =
      String.fromEnvironment('RT_FLAVOR', defaultValue: 'dev');

  static bool get isDev => flavor == 'dev';
}
