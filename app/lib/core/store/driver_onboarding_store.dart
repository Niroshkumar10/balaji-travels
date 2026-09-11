import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the driver onboarding wizard collects that the backend has no
/// column for yet: `rt_drivers`/`rt_vehicles` only cover name, license
/// number, and vehicle category/plate/make/model/color — nothing for
/// language preference, DOB/city, a profile photo, an identity document,
/// insurance, or payout bank/UPI details, and there is no document-upload
/// endpoint at all. Real fields (name, license number, vehicle) still go
/// through ProfileRepository against the real backend; this store is only
/// the local-only extras plus the checklist's "done" flags, so the wizard
/// remembers where a driver left off across app restarts.
///
/// Captured document photos are shown for review in the moment (capture →
/// review → confirm) but are NOT persisted — there's nowhere on the server
/// to send them, and holding multi-MB images in SharedPreferences forever
/// would be the wrong trade. Only the "I completed this step" flag survives.
class DriverOnboardingStore {
  const DriverOnboardingStore._();

  static const _key = 'rt.driverOnboarding';

  static Future<Map<String, dynamic>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>> get() => _load();

  static Future<void> patch(Map<String, dynamic> patch) async {
    final data = await _load();
    data.addAll(patch);
    await _save(data);
  }

  static Future<void> setStepDone(String step, bool done) async {
    final data = await _load();
    final steps = Map<String, dynamic>.from(data['steps'] as Map? ?? {});
    steps[step] = done;
    data['steps'] = steps;
    await _save(data);
  }

  static Future<Set<String>> doneSteps() async {
    final data = await _load();
    final steps = Map<String, dynamic>.from(data['steps'] as Map? ?? {});
    return steps.entries.where((e) => e.value == true).map((e) => e.key).toSet();
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
