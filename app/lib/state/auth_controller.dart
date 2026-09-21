import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/net/result.dart';
import '../core/push/push_service.dart';
import '../core/realtime/socket_client.dart';
import '../core/realtime/socket_diagnostics.dart';
import '../core/repos/auth_repository.dart';
import '../features/driver/driver_controller.dart';

/// Local-only identity note for the diagnostics panel. This is what the APP
/// believes it is about to authenticate as (from the just-issued JWT claims
/// mirrored into Session) — NOT a confirmation from the server. The server
/// never sends the client an explicit "you are now in room user:<id>"
/// acknowledgement; room membership is assigned during the socket handshake
/// (see server/src/sockets/socketAuth.js) and only ever visible in the
/// SERVER's own logs. Never logs the token itself.
void _logAuthIdentity(String label, {required AppRole role, required int userId, int? profileId}) {
  SocketDiagLog.instance.add(
    'AUTH USER ID (local session, $label): userId=$userId role=${role.name}'
    '${profileId != null ? ' profileId(driverId if driver)=$profileId' : ''}',
  );
  SocketDiagLog.instance.add(
    'ROOM (expected, not server-confirmed): user:$userId — the app never '
    'receives an explicit join-room ack; this is only what SHOULD happen.',
  );
}

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.role,
    this.name,
    this.mobile,
    this.profileId,
  });

  final AuthStatus status;
  final AppRole? role;
  final String? name;
  final String? mobile;
  final int? profileId;

  bool get isAuthed => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AppRole? role,
    String? name,
    String? mobile,
    int? profileId,
  }) =>
      AuthState(
        status: status ?? this.status,
        role: role ?? this.role,
        name: name ?? this.name,
        mobile: mobile ?? this.mobile,
        profileId: profileId ?? this.profileId,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required Session session,
    required AuthRepository authRepo,
    required SocketClient socket,
    required Ref ref,
  })  : _session = session,
        _authRepo = authRepo,
        _socket = socket,
        _ref = ref,
        super(const AuthState(status: AuthStatus.unknown)) {
    _bootstrap();
  }

  final Session _session;
  final AuthRepository _authRepo;
  final SocketClient _socket;
  final Ref _ref;

  /// Drop the driver-side controller so its keep-alive timers stop and a fresh
  /// one binds to the new session. Without this, a phone switched from driver
  /// to customer keeps POSTing /drivers/me/heartbeat with a customer token (403).
  void _resetDriverSession() => _ref.invalidate(driverControllerProvider);

  final _statusController = StreamController<AuthStatus>.broadcast();
  Stream<AuthStatus> get statusStream => _statusController.stream;

  void _emit(AuthState s) {
    state = s;
    if (!_statusController.isClosed) _statusController.add(s.status);
  }

  void _bootstrap() {
    if (_session.isAuthenticated) {
      // Always disconnect before connecting so a leftover socket from a
      // previous identity (e.g. a customer session) can never still be the
      // live connection when this one takes over.
      _socket.disconnect();
      if (_session.role != null && _session.userId != null) {
        _logAuthIdentity('bootstrap', role: _session.role!, userId: _session.userId!, profileId: _session.profileId);
      }
      _socket.connect(_session.token!, userId: _session.userId, role: _session.role?.name);
      _emit(AuthState(
        status: AuthStatus.authenticated,
        role: _session.role,
        name: _session.name,
        mobile: _session.mobile,
        profileId: _session.profileId,
      ));
    } else {
      _emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<Result<OtpRequestResult>> sendOtp(String mobile, AppRole role) =>
      _authRepo.requestOtp(mobile: mobile, role: role);

  Future<Result<void>> verifyOtp(String mobile, AppRole role, String code) async {
    final res = await _authRepo.verifyOtp(mobile: mobile, role: role, code: code);
    return switch (res) {
      Ok(:final value) => () async {
          await _session.save(
            token: value.token,
            role: role,
            userId: value.user.id,
            profileId: value.profileId,
            name: value.user.name,
            mobile: mobile,
          );
          _resetDriverSession();
          // Disconnect any existing socket (e.g. a still-open customer
          // session on this device) before connecting fresh with this login's
          // JWT, so the old identity's connection can never linger.
          _socket.disconnect();
          _logAuthIdentity('verifyOtp', role: role, userId: value.user.id, profileId: value.profileId);
          _socket.connect(value.token, userId: value.user.id, role: role.name);
          // A fresh sign-up/login is exactly the case the boot-time delivery
          // in main.dart can't cover: PushService already had a token before
          // this session existed to register it against. Re-deliver it now
          // that there's a valid JWT — a no-op if there's no token yet, or if
          // it already went through at boot for an already-logged-in device.
          PushService.instance.deliverPendingToken();
          _emit(AuthState(
            status: AuthStatus.authenticated,
            role: role,
            name: value.user.name,
            mobile: mobile,
            profileId: value.profileId,
          ));
          return const Ok<void>(null);
        }(),
      Err(:final error) => Err<void>(error),
    };
  }

  Future<void> logout() async {
    await _authRepo.logout();
    await _finishLogout();
  }

  /// Called by the API client on a 401 (session superseded/expired).
  Future<void> forceLogout() => _finishLogout();

  Future<void> _finishLogout() async {
    _resetDriverSession();
    _socket.disconnect();
    await _session.clear();
    _emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> refreshName(String name) async {
    await _session.updateName(name);
    _emit(state.copyWith(name: name));
  }

  @override
  void dispose() {
    _statusController.close();
    super.dispose();
  }
}
