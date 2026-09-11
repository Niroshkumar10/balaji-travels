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

/// Rider details for the current trip — only available from the real-time
/// `ride:assigned` event at the moment a driver accepts (the REST ride
/// enrichment doesn't return the customer's name/rating to the driver side,
/// only vehicle/driver info), so this is best-effort: present right after
/// acceptance, gone if the app is reloaded mid-trip.
class RiderInfo {
  const RiderInfo({required this.name, this.rating, this.phoneMasked});
  final String name;
  final double? rating;
  final String? phoneMasked;
}

class DriverState {
  const DriverState({
    this.online = false,
    this.availability = 'offline',
    this.ride,
    this.offer,
    this.rider,
    this.customerLat,
    this.customerLng,
    this.busy = false,
    this.error,
  });

  final bool online;
  final String availability;
  final Ride? ride;
  final PendingOffer? offer;
  final RiderInfo? rider;
  final double? customerLat;
  final double? customerLng;
  final bool busy;
  final String? error;

  bool get onTrip => ride != null && ride!.status.isActive;
  bool get hasCustomerLocation => customerLat != null && customerLng != null;

  DriverState copyWith({
    bool? online,
    String? availability,
    Ride? ride,
    Object? offer = _sentinel,
    Object? rider = _sentinel,
    double? customerLat,
    double? customerLng,
    bool? busy,
    Object? error = _sentinel,
  }) =>
      DriverState(
        online: online ?? this.online,
        availability: availability ?? this.availability,
        ride: ride ?? this.ride,
        offer: identical(offer, _sentinel) ? this.offer : offer as PendingOffer?,
        rider: identical(rider, _sentinel) ? this.rider : rider as RiderInfo?,
        customerLat: customerLat ?? this.customerLat,
        customerLng: customerLng ?? this.customerLng,
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
  Timer? _heartbeatTimer;
  Position? _lastPos;

  int? get _rideId => state.ride?.id;

  /// How often to force a keep-alive ping regardless of movement. Must be well
  /// under the server's DRIVER_LOCATION_STALE_SECONDS / offline-sweep window,
  /// otherwise a parked driver silently drops out of dispatch.
  static const _heartbeatEvery = Duration(seconds: 20);

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
    _lastPos = pos;
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
    _stopLocationStream();
    state = state.copyWith(online: false, availability: 'offline', busy: false);
    return null;
  }

  /// Make sure GPS is streaming while a trip is active even if the app was
  /// cold-started onto an in-progress ride (i.e. [goOnline] wasn't called this
  /// session). The customer's tracking map depends on these pings.
  Future<void> _ensureTripLocationStream() async {
    if (_posSub != null || !state.onTrip) return;
    final perm = await _location.ensurePermission();
    if (perm.granted) _startLocationStream();
  }

  void _startLocationStream() {
    _posSub?.cancel();
    _posSub = _location.stream(distanceFilterM: 12).listen((pos) {
      _lastPos = pos;
      _pingLocation(pos);
    });

    // Movement-based pings stop the moment the driver stands still; this timer
    // keeps the presence fresh so dispatch (and the offline sweep) keep them in.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatEvery, (_) async {
      if (!state.online && !state.onTrip) return;
      final pos = await _location.current() ?? _lastPos;
      if (pos == null) return;
      _lastPos = pos;
      _pingLocation(pos, restFallback: true);
    });
  }

  void _pingLocation(Position pos, {bool restFallback = false}) {
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
    // The socket emit is fire-and-forget and silently no-ops when disconnected;
    // on the periodic tick also hit REST so a dropped socket never makes the
    // driver invisible to dispatch.
    if (restFallback) {
      unawaited(_profiles.heartbeat(
        lat: pos.latitude,
        lng: pos.longitude,
        bearing: pos.heading,
        speedKmph: pos.speed * 3.6,
      ));
    }
  }

  void _stopLocationStream() {
    _posSub?.cancel();
    _posSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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

  /// Real ride cancellation — used by the "Start trip?" checkpoint's Cancel
  /// button. Frees the driver back to available on success.
  Future<String?> cancelRide({String? reason}) async {
    final id = _rideId;
    if (id == null) return 'No active ride';
    state = state.copyWith(busy: true);
    final res = await _rides.cancel(id, reason: reason);
    state = state.copyWith(busy: false);
    final err = res.when(ok: (_) => null, err: (e) => e.message);
    if (err == null) {
      state = DriverState(online: state.online, availability: state.online ? 'available' : 'offline');
    }
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
        if (ride != null) {
          _socket.emitAck('ride:resync', {'rideId': ride.id});
          _ensureTripLocationStream();
        }
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
      case 'ride:customer_location':
        if (_rideId != null && (d['rideId'] as num?)?.toInt() == _rideId) {
          state = state.copyWith(
            customerLat: (d['lat'] as num?)?.toDouble(),
            customerLng: (d['lng'] as num?)?.toDouble(),
          );
        }
      case 'ride:assigned':
        final c = _map(d['customer']);
        if (c.isNotEmpty) {
          state = state.copyWith(
            rider: RiderInfo(
              name: c['name']?.toString() ?? 'Rider',
              phoneMasked: c['phoneMasked']?.toString(),
            ),
          );
        }
        _refetchActive();
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
    _stopLocationStream();
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
  // Surface the failure so the screen can show why + offer a retry, instead of
  // collapsing every error into a blank "Profile unavailable".
  return res.when(ok: (p) => p, err: (e) => throw e);
});
