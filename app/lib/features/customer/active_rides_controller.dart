import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/realtime/socket_client.dart';
import '../../core/repos/ride_repository.dart';
import '../../state/providers.dart';

/// Every concurrent active ride for the customer (one per service type is
/// now possible — a local ride, a rental and an outstation trip can each be
/// in progress at once, see rideService.assertNoBookingConflict() on the
/// server). Powers the home screen's "ride in progress" cards.
///
/// Deliberately separate from RideSessionController, which still tracks
/// exactly one ride at a time (the tracking screen, driver location, OTP,
/// cancel) — nothing about that single-ride flow changes here.
class ActiveRidesController extends StateNotifier<List<Ride>> {
  ActiveRidesController(this._rides, this._socket) : super(const []) {
    _sub = _socket.events.listen(_onEvent);
  }

  final RideRepository _rides;
  final SocketClient _socket;
  late final StreamSubscription<SocketEvent> _sub;

  // Same ride-lifecycle event set RideSessionController reacts to, but
  // un-scoped to a single rideId — any of the customer's rides changing is
  // reason enough to re-fetch the whole active list.
  static const _refreshEvents = {
    'ride:searching',
    'ride:pending_admin_assignment',
    'ride:driver_assigned',
    'ride:status',
    'ride:driver_arrived',
    'ride:started',
    'ride:driver_completed',
    'ride:payment_pending',
    'ride:payment_update',
    'ride:completed',
    'ride:cancelled',
    'ride:no_drivers',
  };

  Future<void> refresh() async {
    final res = await _rides.activeAll();
    res.when(
      ok: (rides) => state = rides,
      err: (_) {/* keep last known list */},
    );
  }

  void _onEvent(SocketEvent e) {
    if (_refreshEvents.contains(e.name)) refresh();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final activeRidesProvider =
    StateNotifierProvider<ActiveRidesController, List<Ride>>((ref) {
  return ActiveRidesController(
    ref.watch(rideRepoProvider),
    ref.watch(socketClientProvider),
  );
});
