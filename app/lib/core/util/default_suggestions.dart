import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../../state/providers.dart';

/// Fixed "suggested place" lists shown instantly on the home screen and
/// "Plan your ride" — no reverse-geocode + N sequential autocomplete calls
/// up front (that's what made suggestions take a while to appear before).
/// Each label is only resolved to real coordinates lazily, the moment the
/// rider actually taps it or favorites it.
class DefaultSuggestions {
  const DefaultSuggestions._();

  static const nearYou = [
    'Coimbatore Airport',
    'Gandhipuram Bus Stand',
    'Coimbatore Railway Station',
    'Prozone Mall, Coimbatore',
    'Fun Republic Mall, Coimbatore',
    'KMCH, Coimbatore',
    'SITRA, Coimbatore',
    'Sri Ramakrishna College, Coimbatore',
    'Karpagam College of Engineering, Coimbatore',
  ];

  static const outstation = [
    'Isha Yoga Center, Coimbatore',
    'Perur Pateeswarar Temple, Coimbatore',
    'Siruvani Falls and Dam, Coimbatore',
    'Marudamalai Murugan Temple, Coimbatore',
    'Ooty, Tamil Nadu',
    'Valparai, Tamil Nadu',
    'Kodaikanal, Tamil Nadu',
    'Black Thunder, Tamil Nadu',
    'Yercaud, Tamil Nadu',
    'Alleppey, Kerala',
    'Wayanad, Kerala',
    'Wonderla, Kerala',
  ];
}

/// Resolves one suggestion label to a real place (first usable autocomplete
/// result, then its coordinates) — called on tap/favorite, not eagerly.
Future<LatLngPoint?> resolveSuggestion(WidgetRef ref, String label, {double? lat, double? lng}) async {
  final res = await ref.read(miscRepoProvider).autocomplete(label, lat: lat, lng: lng);
  final usable = (res.valueOrNull ?? const <PlacePrediction>[]).where((p) => (p.placeId ?? '').isNotEmpty);
  if (usable.isEmpty) return null;
  final details = await ref.read(miscRepoProvider).placeDetails(usable.first.placeId!);
  return details.valueOrNull;
}
