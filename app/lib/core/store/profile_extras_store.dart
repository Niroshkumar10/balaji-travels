import 'package:shared_preferences/shared_preferences.dart';

/// Profile fields the backend doesn't have yet (`rt_customers` has no
/// birthday or UPI-VPA column) — stored locally, same pattern as the other
/// on-device stores. Real fields (name, email) still go through
/// ProfileRepository.updateCustomer against the real backend.
class ProfileExtrasStore {
  const ProfileExtrasStore._();

  static const _kDob = 'rt.profile.dob';
  static const _kUpi = 'rt.profile.upi';

  static Future<String?> dob() async => (await SharedPreferences.getInstance()).getString(_kDob);
  static Future<void> setDob(String value) async =>
      (await SharedPreferences.getInstance()).setString(_kDob, value);

  static Future<String?> upi() async => (await SharedPreferences.getInstance()).getString(_kUpi);
  static Future<void> setUpi(String value) async =>
      (await SharedPreferences.getInstance()).setString(_kUpi, value);
}
