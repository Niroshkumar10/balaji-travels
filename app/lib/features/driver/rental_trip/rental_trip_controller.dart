import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/repos/ride_repository.dart';
import '../../../state/providers.dart';

/// Every Rental/Trip booking the driver holds — currently reserved (accepted,
/// not yet started) or awaiting their confirmation — for the "Rental and
/// Trip" screen. Modelled on customer/active_rides_controller.dart:
/// GET /rides/active/all now serves both roles (see rideService.
/// listActiveRides()'s driver branch, rideRepo.findAllHeldForDriver()).
///
/// Deliberately separate from DriverController, which only ever tracks the
/// ONE ride currently occupying the driver's exclusive active_driver_id slot
/// (the live-trip/navigation screen) — a reserved booking never appears
/// there until the driver taps Start Navigation (see
/// DriverController.startReservedNavigation()).
class RentalTripController extends StateNotifier<List<Ride>> {
  RentalTripController(this._rides, this._socket) : super(const []) {
    _sub = _socket.events.listen(_onEvent);
  }

  final RideRepository _rides;
  final SocketClient _socket;
  late final StreamSubscription<SocketEvent> _sub;

  static const _refreshEvents = {
    'ride:status',
    'ride:assigned',
    'ride:cancelled',
    'ride:completed',
    'ride:payment_update',
    'ride:assignment_pending',
    'ride:assignment_reserved',
  };

  Future<void> refresh() async {
    final res = await _rides.activeAll();
    res.when(
      ok: (rides) => state = rides.where((r) => !r.isLocal).toList(),
      err: (_) {/* keep last known list */},
    );
  }

  Future<String?> accept(int rideId) async {
    final res = await _rides.acceptAssignment(rideId);
    final err = res.when<String?>(ok: (_) => null, err: (e) => e.message);
    await refresh();
    return err;
  }

  Future<String?> decline(int rideId, {String? reason}) async {
    final res = await _rides.declineAssignment(rideId, reason: reason);
    final err = res.when<String?>(ok: (_) => null, err: (e) => e.message);
    await refresh();
    return err;
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

final rentalTripProvider = StateNotifierProvider<RentalTripController, List<Ride>>((ref) {
  return RentalTripController(
    ref.watch(rideRepoProvider),
    ref.watch(socketClientProvider),
  );
});
