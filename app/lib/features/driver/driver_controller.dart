import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/location/location_service.dart';
import '../../core/models/models.dart';
import '../../core/net/result.dart';
import '../../core/realtime/socket_client.dart';
import '../../core/repos/payment_repository.dart';
import '../../core/repos/profile_repository.dart';
import '../../core/repos/ride_repository.dart';
import '../../state/providers.dart';

class PendingOffer {
  const PendingOffer({
    required this.rideId,
    required this.pickup,
    required this.drop,
    required this.distanceToPickupM,
    required this.tripDistanceM,
    required this.estFare,
    required this.vehicleCategory,
    required this.expiresInSec,
  });

  final int rideId;
  final LatLngPoint pickup;
  final LatLngPoint drop;
  final int distanceToPickupM;
  final int tripDistanceM;
  final double estFare;
  final String vehicleCategory;
  final int expiresInSec;
}

class DriverState {
  const DriverState({
    this.online = false,
    this.availability = 'offline',
    this.ride,
    this.offer,
    this.busy = false,
    this.error,
  });

  final bool online;
  final String availability;
  final Ride? ride;
  final PendingOffer? offer;
  final bool busy;
  final String? error;

  bool get onTrip => ride != null && ride!.status.isActive;

  DriverState copyWith({
    bool? online,
    String? availability,
    Ride? ride,
    Object? offer = _sentinel,
    bool? busy,
    Object? error = _sentinel,
  }) =>
      DriverState(
        online: online ?? this.online,
        availability: availability ?? this.availability,
        ride: ride ?? this.ride,
        offer: identical(offer, _sentinel) ? this.offer : offer as PendingOffer?,
        busy: busy ?? this.busy,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

class DriverController extends StateNotifier<DriverState> {
  DriverController({
    required SocketClient socket,
    required RideRepository rides,
    required ProfileRepository profiles,
    required PaymentRepository payments,
    required LocationService location,
  })  : _socket = socket,
        _rides = rides,
        _profiles = profiles,
        _payments = payments,
        _location = location,
        super(const DriverState()) {
    _sub = _socket.events.listen(_onEvent);
    loadActive();
  }

  final SocketClient _socket;
  final RideRepository _rides;
  final ProfileRepository _profiles;
  final PaymentRepository _payments;
  final LocationService _location;

  late final StreamSubscription<SocketEvent> _sub;
  StreamSubscription<Position>? _posSub;

  int? get _rideId => state.ride?.id;

  // ── presence ──────────────────────────────────────────────────────────────
  Future<String?> goOnline() async {
    state = state.copyWith(busy: true, error: null);
    final perm = await _location.ensurePermission();
    if (!perm.granted) {
      state = state.copyWith(busy: false);
      return 'Location permission is required to go online';
    }
    final pos = await _location.current();
    if (pos == null) {
      state = state.copyWith(busy: false);
      return 'Could not get your location';
    }
    final ack = await _socket.emitAck('driver:online', {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
    if (ack['ok'] != true) {
      // REST fallback
      final res = await _profiles.goOnline(lat: pos.latitude, lng: pos.longitude);
      final err = res.when(ok: (_) => null, err: (e) => e.message);
      if (err != null) {
        state = state.copyWith(busy: false);
        return err;
      }
    }
    state = state.copyWith(online: true, availability: 'available', busy: false);
    _startLocationStream();
    return null;
  }

  Future<String?> goOffline() async {
    state = state.copyWith(busy: true);
    final ack = await _socket.emitAck('driver:offline', {});
    if (ack['ok'] != true) {
      final res = await _profiles.goOffline();
      final err = res.when(ok: (_) => null, err: (e) => e.message);
      if (err != null) {
        state = state.copyWith(busy: false);
        return err;
      }
    }
    _posSub?.cancel();
    _posSub = null;
    state = state.copyWith(online: false, availability: 'offline', busy: false);
    return null;
  }

  void _startLocationStream() {
    _posSub?.cancel();
    _posSub = _location.stream(distanceFilterM: 12).listen((pos) {
      final payload = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'bearing': pos.heading,
        'speedKmph': pos.speed * 3.6,
      };
      if (state.onTrip && _rideId != null) {
        _socket.emit('driver:location', {...payload, 'rideId': _rideId});
      } else {
        _socket.emit('driver:heartbeat', payload);
      }
    });
  }

  // ── dispatch offers ──────────────────────────────────────────────────────
  Future<String?> respondOffer(int rideId, bool accept) async {
    state = state.copyWith(busy: true);
    final ack = await _socket.emitAck('ride:offer_response', {
      'rideId': rideId,
      'accept': accept,
    });
    state = state.copyWith(busy: false, offer: null);
    if (ack['ok'] == true && accept) {
      await _refetchActive();
      return null;
    }
    if (accept && ack['ok'] != true) {
      // REST fallback
      final res = await _rides.offerResponse(rideId, accept);
      final ok = res.valueOrNull?['ok'] == true;
      if (ok) {
        await _refetchActive();
        return null;
      }
      return (ack['message'] as String?) ?? 'Ride already taken';
    }
    return null;
  }

  // ── trip milestones ──────────────────────────────────────────────────────
  Future<String?> _milestone(
    String socketEvent,
    Map<String, dynamic> extra,
    Future<Result<Ride>> Function() restFallback,
  ) async {
    final id = _rideId;
    if (id == null) return 'No active ride';
    state = state.copyWith(busy: true);
    final ack = await _socket.emitAck(socketEvent, {'rideId': id, ...extra});
    state = state.copyWith(busy: false);
    if (ack['ok'] == true) {
      await _refetchActive();
      return null;
    }
    final res = await restFallback();
    final err = res.when<String?>(ok: (_) => null, err: (e) => e.message);
    await _refetchActive();
    return err ?? (ack['message'] as String?);
  }

  Future<String?> startNavigation() => _milestone('ride:enroute', {}, () => _rides.enroute(_rideId!));
  Future<String?> markArrived() => _milestone('ride:arrived', {}, () => _rides.arrived(_rideId!));
  Future<String?> startRide(String otp) =>
      _milestone('ride:start', {'otp': otp}, () => _rides.start(_rideId!, otp));
  Future<String?> completeRide(int waitingMinutes) => _milestone(
        'ride:complete',
        {'waitingMinutes': waitingMinutes},
        () => _rides.complete(_rideId!, waitingMinutes: waitingMinutes),
      );

  Future<String?> settleCash() async {
    final id = _rideId;
    if (id == null) return 'No active ride';
    state = state.copyWith(busy: true);
    final res = await _payments.settleCash(id);
    state = state.copyWith(busy: false);
    final err = res.when(ok: (_) => null, err: (e) => e.message);
    await _refetchActive();
    return err;
  }

  // ── data ─────────────────────────────────────────────────────────────────
  Future<void> loadActive() async {
    final res = await _rides.active();
    res.when(
      ok: (ride) {
        state = state.copyWith(
          ride: ride,
          availability: ride != null && ride.status.isActive ? 'on_trip' : state.availability,
        );
        if (ride != null) _socket.emitAck('ride:resync', {'rideId': ride.id});
      },
      err: (_) {},
    );
  }

  Future<void> _refetchActive() async {
    final id = _rideId;
    if (id == null) {
      await loadActive();
      return;
    }
    final res = await _rides.get(id);
    res.when(
      ok: (ride) {
        // ride finished → clear it so the dashboard frees up
        state = state.copyWith(
          ride: ride,
          availability: ride.status.isActive ? 'on_trip' : (state.online ? 'available' : 'offline'),
        );
      },
      err: (_) {},
    );
  }

  void clearFinishedRide() {
    if (state.ride != null && !state.ride!.status.isActive) {
      state = DriverState(
        online: state.online,
        availability: state.online ? 'available' : 'offline',
      );
    }
  }

  void _onEvent(SocketEvent e) {
    final d = e.data;
    switch (e.name) {
      case 'ride:offer':
        state = state.copyWith(
          offer: PendingOffer(
            rideId: (d['rideId'] as num).toInt(),
            pickup: LatLngPoint.fromJson(_map(d['pickup'])),
            drop: LatLngPoint.fromJson(_map(d['drop'])),
            distanceToPickupM: (d['distanceToPickupM'] as num?)?.toInt() ?? 0,
            tripDistanceM: (d['tripDistanceM'] as num?)?.toInt() ?? 0,
            estFare: (d['estFare'] as num?)?.toDouble() ?? 0,
            vehicleCategory: d['vehicleCategory']?.toString() ?? 'hatchback',
            expiresInSec: (d['expiresInSec'] as num?)?.toInt() ?? 20,
          ),
        );
      case 'ride:offer_revoked':
        if (state.offer?.rideId == (d['rideId'] as num?)?.toInt()) {
          state = state.copyWith(offer: null);
        }
      case 'ride:assigned':
      case 'ride:status':
      case 'ride:cancelled':
      case 'ride:payment_update':
      case 'ride:completed':
        _refetchActive();
      default:
        break;
    }
  }

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

  @override
  void dispose() {
    _sub.cancel();
    _posSub?.cancel();
    super.dispose();
  }
}

final driverControllerProvider =
    StateNotifierProvider<DriverController, DriverState>((ref) {
  return DriverController(
    socket: ref.watch(socketClientProvider),
    rides: ref.watch(rideRepoProvider),
    profiles: ref.watch(profileRepoProvider),
    payments: ref.watch(paymentRepoProvider),
    location: ref.watch(locationServiceProvider),
  );
});

final driverProfileProvider = FutureProvider.autoDispose<DriverProfile?>((ref) async {
  final res = await ref.watch(profileRepoProvider).getDriver();
  return res.valueOrNull;
});
