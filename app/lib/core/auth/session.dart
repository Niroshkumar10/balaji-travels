import 'package:shared_preferences/shared_preferences.dart';

enum AppRole { customer, driver }

AppRole? _parseRole(String? s) => switch (s) {
      'customer' => AppRole.customer,
      'driver' => AppRole.driver,
      _ => null,
    };

/// Persisted auth session: the JWT plus the identity it belongs to. Backed by
/// SharedPreferences. The token is the ONLY credential — the backend re-checks
/// it against the live session on every request, so clearing it here is a real
/// logout.
class Session {
  Session._(this._prefs);

  final SharedPreferences _prefs;

  static const _kToken = 'rt.token';
  static const _kRole = 'rt.role';
  static const _kUserId = 'rt.userId';
  static const _kProfileId = 'rt.profileId';
  static const _kName = 'rt.name';
  static const _kMobile = 'rt.mobile';
  static const _kOnboarded = 'rt.onboarded';

  static Future<Session> load() async =>
      Session._(await SharedPreferences.getInstance());

  String? get token => _prefs.getString(_kToken);
  AppRole? get role => _parseRole(_prefs.getString(_kRole));
  int? get userId => _prefs.getInt(_kUserId);
  int? get profileId => _prefs.getInt(_kProfileId);
  String? get name => _prefs.getString(_kName);
  String? get mobile => _prefs.getString(_kMobile);
  bool get isAuthenticated => (token?.isNotEmpty ?? false) && role != null;
  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  Future<void> save({
    required String token,
    required AppRole role,
    required int userId,
    required int profileId,
    String? name,
    String? mobile,
  }) async {
    await _prefs.setString(_kToken, token);
    await _prefs.setString(_kRole, role.name);
    await _prefs.setInt(_kUserId, userId);
    await _prefs.setInt(_kProfileId, profileId);
    if (name != null) await _prefs.setString(_kName, name);
    if (mobile != null) await _prefs.setString(_kMobile, mobile);
  }

  Future<void> updateName(String name) => _prefs.setString(_kName, name);

  Future<void> clear() async {
    for (final k in [_kToken, _kRole, _kUserId, _kProfileId, _kName, _kMobile]) {
      await _prefs.remove(k);
    }
  }
}
