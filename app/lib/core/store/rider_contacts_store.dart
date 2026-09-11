import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A contact the rider can book a ride "for" — there is no backend field for
/// this (`rt_rides` has no rider-other-than-booker column), so this is a
/// local, per-device address book, same pattern as [RecentSearchStore]. The
/// chosen name is carried as a display label only.
class RiderContact {
  const RiderContact({required this.name, required this.phone});
  final String name;
  final String phone;

  factory RiderContact.fromJson(Map<String, dynamic> j) =>
      RiderContact(name: j['name'] as String, phone: j['phone'] as String? ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

class RiderContactsStore {
  const RiderContactsStore._();

  static const _key = 'rt.riderContacts';

  static Future<List<RiderContact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((s) {
          try {
            return RiderContact.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<RiderContact>()
        .toList();
  }

  static Future<void> add(RiderContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [...await load(), contact];
    await prefs.setStringList(_key, next.map((c) => jsonEncode(c.toJson())).toList());
  }
}
