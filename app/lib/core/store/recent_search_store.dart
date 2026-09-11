import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// The rider's last few picked destinations, most recent first. Backed by
/// SharedPreferences (same pattern as [Session]) — purely a local, per-device
/// convenience list, not synced to the backend.
class RecentSearchStore {
  const RecentSearchStore._();

  static const _key = 'rt.recentSearches';
  static const _max = 6;

  static Future<List<LatLngPoint>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((s) {
          try {
            return LatLngPoint.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<LatLngPoint>()
        .toList();
  }

  /// Pushes [point] to the front, de-duplicating by address text, capped at
  /// [_max] entries.
  static Future<void> add(LatLngPoint point) async {
    if (point.addr == null || point.addr!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = [point, ...current.where((p) => p.addr != point.addr)].take(_max).toList();
    await prefs.setStringList(_key, next.map((p) => jsonEncode(p.toJson())).toList());
  }
}
