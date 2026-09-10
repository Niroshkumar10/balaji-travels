import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../state/providers.dart';

/// One-shot current position (null until permission + a fix are available).
final currentPositionProvider = FutureProvider.autoDispose<Position?>((ref) async {
  final svc = ref.watch(locationServiceProvider);
  final perm = await svc.ensurePermission();
  if (!perm.granted) return null;
  return svc.current();
});

/// Continuous position stream — the app's live "where am I now". Updates on
/// every meaningful move (distanceFilter in LocationService.stream). Keeps
/// alive while at least one screen is listening.
final positionStreamProvider = StreamProvider<Position>((ref) async* {
  final svc = ref.watch(locationServiceProvider);
  final perm = await svc.ensurePermission();
  if (!perm.granted) return;

  // seed with the last-known / current fix so the map isn't empty for the
  // first few seconds
  final first = await svc.current();
  if (first != null) yield first;

  yield* svc.stream(distanceFilterM: 8);
});
