import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/realtime/socket_client.dart';
import '../../core/repos/ride_repository.dart';
import '../../state/providers.dart';

class RideSessionState {
  const RideSessionState({
    this.ride,
    this.driverLat,
    this.driverLng,
    this.driverBearing,
    this.etaSeconds,
    this.loading = false,
    this.error,
  });

  final Ride? ride;
  final double? driverLat;
  final double? driverLng;
  final double? driverBearing;
  final int? etaSeconds;
  final bool loading;
  final String? error;

  RideSessionState copyWith({
    Ride? ride,
    double? driverLat,
    double? driverLng,
    double? driverBearing,
    int? etaSeconds,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      RideSessionState(
        ride: ride ?? this.ride,
        driverLat: driverLat ?? this.driverLat,
        driverLng: driverLng ?? this.driverLng,
        driverBearing: driverBearing ?? this.driverBearing,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class RideSessionController extends StateNotifier<RideSessionState> {
  RideSessionController(this._rides, this._socket) : super(const RideSessionState()) {
    _sub = _socket.events.listen(_onEvent);
  }

  final RideRepository _rides;
  final SocketClient _socket;
  late final StreamSubscription<SocketEvent> _sub;

  int? get _rideId => state.ride?.id;

  Future<void> loadActive() async {
    state = state.copyWith(loading: true, clearError: true);
    final res = await _rides.active();
    res.when(
      ok: (ride) {
        state = RideSessionState(ride: ride);
        if (ride != null) _socket.emitAck('ride:resync', {'rideId': ride.id});
      },
      err: (e) => state = state.copyWith(loading: false, error: e.message),
    );
  }

  Future<void> attach(int rideId) async {
    state = state.copyWith(loading: true, clearError: true);
    final res = await _rides.get(rideId);
    res.when(
      ok: (ride) {
        state = RideSessionState(
          ride: ride,
          driverLat: ride.driverLat,
          driverLng: ride.driverLng,
        );
        _socket.emitAck('ride:resync', {'rideId': rideId});
      },
      err: (e) => state = state.copyWith(loading: false, error: e.message),
    );
  }

  Future<void> _refetch() async {
    final id = _rideId;
    if (id == null) return;
    final res = await _rides.get(id);
    res.when(
      ok: (ride) => state = state.copyWith(
        ride: ride,
        driverLat: ride.driverLat,
        driverLng: ride.driverLng,
      ),
      err: (_) {/* keep last known */},
    );
  }

  void _onEvent(SocketEvent e) {
    final data = e.data;
    final id = _rideId;
    // ride:driver_location arrives even before we've loaded — accept if it matches
    final evtRideId = (data['rideId'] as num?)?.toInt();
    if (id != null && evtRideId != null && evtRideId != id) return;

    switch (e.name) {
      case 'ride:driver_location':
        state = state.copyWith(
          driverLat: (data['lat'] as num?)?.toDouble(),
          driverLng: (data['lng'] as num?)?.toDouble(),
          driverBearing: (data['bearing'] as num?)?.toDouble(),
          etaSeconds: (data['etaSeconds'] as num?)?.toInt(),
        );
      case 'ride:searching':
      case 'ride:driver_assigned':
      case 'ride:status':
      case 'ride:driver_arrived':
      case 'ride:started':
      case 'ride:driver_completed':
      case 'ride:payment_pending':
      case 'ride:payment_update':
      case 'ride:completed':
      case 'ride:cancelled':
      case 'ride:no_drivers':
        _refetch();
      default:
        break;
    }
  }

  Future<String?> cancel({String? reason}) async {
    final id = _rideId;
    if (id == null) return 'No active ride';
    final res = await _rides.cancel(id, reason: reason);
    return res.when(
      ok: (ride) {
        state = state.copyWith(ride: ride);
        return null;
      },
      err: (e) => e.message,
    );
  }

  void clear() => state = const RideSessionState();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final rideSessionProvider =
    StateNotifierProvider<RideSessionController, RideSessionState>((ref) {
  return RideSessionController(
    ref.watch(rideRepoProvider),
    ref.watch(socketClientProvider),
  );
});
