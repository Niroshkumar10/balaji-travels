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

  // Fast path: the OS's cached last-known fix is near-instant (no GPS wait)
  // — yield it first so the map/pickup point shows immediately instead of
  // sitting empty while a fresh fix is acquired (LocationService.current()
  // can take up to ~12s cold). The real fix below supersedes it the moment
  // it arrives; this is never used as a substitute for one.
  final last = await svc.lastKnown();
  if (last != null) yield last;

  final fresh = await svc.current();
  if (fresh != null) yield fresh;

  yield* svc.stream(distanceFilterM: 8);
});
