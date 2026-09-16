import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import 'socket_diagnostics.dart';

// Plain print() so the line lands in `adb logcat` even for a --release build
// (dart:developer log() needs the VM service, which release builds don't run).
// Filter with:  adb logcat | grep RT-
//
// Also mirrored into SocketDiagLog (in-memory, on-device) so the temporary
// diagnostics screen shows exactly the same sequence without needing ADB —
// this is the ONE place every socket log line in this file passes through,
// so nothing below needed a second, separate logging call.
void _log(String msg) {
  print('[RT-SOCKET] $msg'); // ignore: avoid_print
  SocketDiagLog.instance.add('SOCKET: $msg');
}

/// Bump this string with every socket-layer fix. Shown on the driver debug
/// strip so a screenshot proves (or disproves) that a test actually ran the
/// current build — "stale APK" has been the recurring false lead in this bug.
const socketClientBuildMarker = 'sock-2026-09-11-gen-guard';

/// A single server→client event.
class SocketEvent {
  const SocketEvent(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

enum SocketConnState { disconnected, connecting, connected }

/// Wraps `socket_io_client` with:
///  - JWT auth on the handshake (never trusts payload ids — matches the server)
///  - automatic reconnection with re-auth
///  - a single broadcast [events] stream for all ride/notification events
///  - `emitAck` for request/response calls
///
/// Reconnect handling (the brief's §18): on `connect` the caller should
/// re-`emitAck('ride:resync', {rideId})` to pull the authoritative state.
class SocketClient {
  SocketClient() {
    _log('initialized (SocketClient instance created)');
    _watchConnectivity();
  }

  io.Socket? _socket;
  String? _token;
  bool _fatalAuth = false;
  int _generation = 0;
  // Diagnostic-only — never used to authenticate anything. Set from whatever
  // the caller (auth_controller) tells us at connect() time, purely so the
  // "SOCKET AUTH BUILD" log line can show which session identity a given
  // handshake was built for, without touching the token itself.
  int? _lastUserId;
  String? _lastRole;
  final _events = StreamController<SocketEvent>.broadcast();
  final _connState = StreamController<SocketConnState>.broadcast();
  SocketConnState _state = SocketConnState.disconnected;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Invoked once when the server rejects the handshake for an auth reason
  /// (token superseded / expired / invalid). Retrying is pointless — the stored
  /// token is dead — so the app should force a logout. Set by the provider.
  void Function()? onAuthFailure;

  /// Handshake errors the server sends (see sockets/socketAuth.js `deny(...)`)
  /// that mean "this token will never work" — stop reconnecting on these.
  static const _authErrorCodes = <String>{
    'AUTH_REQUIRED',
    'BAD_TOKEN',
    'ACCOUNT_INACTIVE',
    'SESSION_SUPERSEDED',
    'SESSION_EXPIRED',
    'AUTH_ERROR',
  };

  static const _serverEvents = <String>[
    'ride:searching',
    'ride:offer',
    'ride:offer_revoked',
    'ride:driver_assigned',
    'ride:assigned',
    'ride:status',
    'ride:driver_arrived',
    'ride:started',
    'ride:driver_location',
    'ride:customer_location',
    'ride:driver_completed',
    'ride:payment_pending',
    'ride:payment_update',
    'ride:completed',
    'ride:cancelled',
    'ride:no_drivers',
    'notification',
  ];

  Stream<SocketEvent> get events => _events.stream;
  Stream<SocketConnState> get connState => _connState.stream;
  SocketConnState get state => _state;
  bool get isConnected => _state == SocketConnState.connected;

  /// Socket.IO's own reconnection backoff can take up to 8s per attempt, and
  /// on Android the whole timer can simply be paused while the app is
  /// backgrounded — so "wait for the library to retry" isn't enough on its
  /// own. Watching OS-level connectivity directly (same pattern Microlab's
  /// SocketService uses) lets us force an immediate reconnect the moment the
  /// network is back, rather than however long the internal timer takes.
  void _watchConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        _log('connectivity restored — ensuring socket connection');
        ensureConnected();
      }
    });
  }

  /// Nudge the connection back to life if we're logged in but not currently
  /// connected. Safe to call opportunistically and often — a no-op if never
  /// logged in or already connected. This is the "make sure the socket is up
  /// before relying on it" hook: called on connectivity restore, app resume,
  /// and right before the driver goes online / on every presence heartbeat.
  void ensureConnected() {
    final t = _token;
    if (t == null) return; // never logged in, or a forced logout cleared it
    if (_socket != null && _socket!.connected) return;
    _log('ensureConnected(): state=$_state — reconnecting');
    connect(t);
  }

  /// [userId]/[role] are diagnostic-only labels for the identity this connect
  /// call is being made on behalf of — never sent to the server and never
  /// used to decide anything below. The server only ever trusts the JWT
  /// inside `auth`.
  void connect(String token, {int? userId, String? role}) {
    if (userId != null) _lastUserId = userId;
    if (role != null) _lastRole = role;

    if (_socket != null) {
      // Same identity, already wired up — just make sure it's live.
      if (token == _token && !_fatalAuth) {
        _log('connect(): same identity, connected=${_socket!.connected} '
            '(socket instance recreated=false)');
        if (!_socket!.connected) _socket!.connect();
        return;
      }
      // Identity changed (account / role switch), or the last token was
      // rejected. The handshake auth is baked into the socket at build time and
      // a running connection keeps its old identity, so offers addressed to the
      // new user's room never arrive. Tear the socket down and rebuild it.
      _log('connect(): token changed → rebuilding socket (gen ${_generation + 1})');
      disconnect();
    }
    _token = token;
    _fatalAuth = false;
    _setState(SocketConnState.connecting);

    // SAFE diagnostic only — never the token itself, never used for auth.
    final fp = token.length > 6 ? token.substring(token.length - 6) : token;
    _log('SOCKET AUTH BUILD: sessionUserId=${_lastUserId ?? "?"} '
        'sessionRole=${_lastRole ?? "?"} tokenPresent=true '
        'tokenFingerprint=…$fp socket instance recreated=true');

    // Every socket gets a generation number. `_events` is one long-lived
    // broadcast stream shared across every socket this client ever builds; a
    // just-disposed socket can still have an in-flight message land in its
    // `.on(...)` closures during the teardown race, and without this guard
    // that stale message would be pushed into `_events` and misread as
    // belonging to the CURRENT identity (e.g. a customer-only event landing on
    // a driver session right after a role switch). Every handler below checks
    // `myGen == _generation` before doing anything.
    final myGen = ++_generation;
    _log('connecting to ${AppConfig.socketUrl} (gen $myGen)'); // never log the token itself

    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          // WebSocket first. The Apache/Passenger proxy in front of this domain
          // forwards the WS upgrade fine (other clients sustain transport=
          // websocket here) but buffers Socket.IO's long-polling XHR, so a
          // polling-only client never completes the namespace handshake.
          // 'polling' stays as a fallback for networks that block WS.
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setAuth({'token': token})
          // ROOT CAUSE of the customer→driver identity bug: socket_io_client's
          // top-level io(uri, opts) keeps a GLOBAL cache of Manager objects
          // keyed only by scheme://host:port (see package
          // socket_io_client/socket_io_client.dart `_lookup`). Since
          // AppConfig.socketUrl is a bare host with no path, every connect()
          // call in this app resolves to the SAME cache key. Manager.socket()
          // then returns whatever Socket object already lives in its `nsps['/']`
          // map instead of building a new one — and that map is never cleared
          // by dispose()/disconnect() (Manager.destroy() only closes the
          // transport, it never removes the entry). So the driver's "new"
          // socket after OTP login was literally the same Dart Socket object
          // created for the earlier customer session, still holding the
          // customer JWT in its `auth` field — which is exactly why the server
          // authenticated it as userId=2 while the app believed it had just
          // connected as userId=13 (same socket id on both sides was the
          // giveaway). forceNew makes every call here skip that cache and
          // Manager.nsps lookup entirely, guaranteeing a brand-new Manager +
          // Socket + engine.io connection is built fresh from the CURRENT
          // auth token every single time this method reaches this point.
          .enableForceNew()
          .build(),
    );

    socket.onConnect((_) {
      if (myGen != _generation) {
        _log('gen $myGen CONNECTED but superseded (current gen $_generation) — ignoring, disposing');
        socket.dispose();
        return;
      }
      _log('gen $myGen CONNECTED (sid=${socket.id})');
      _setState(SocketConnState.connected);
    });
    socket.onDisconnect((reason) {
      if (myGen != _generation) return;
      _log('gen $myGen disconnected: $reason');
      _setState(SocketConnState.disconnected);
    });
    // The server rejects a bad handshake with `connect_error` carrying the
    // reason string (sockets/socketAuth.js). onError is post-connection noise —
    // don't treat it as fatal.
    socket.onConnectError((data) {
      if (myGen != _generation) return;
      _onConnectError(data);
    });
    socket.onError((e) {
      if (myGen != _generation) return;
      _log('gen $myGen error: $e');
    });
    socket.onReconnectAttempt((n) {
      if (myGen != _generation) return;
      _log('gen $myGen reconnect attempt $n');
      _setState(SocketConnState.connecting);
    });
    // Pure observers — log-only, no effect on the reconnection behaviour
    // itself (that's still entirely enableReconnection()/backoff above).
    socket.onReconnect((n) {
      if (myGen != _generation) return;
      _log('gen $myGen reconnect SUCCESS after $n attempt(s)');
    });
    socket.onReconnectFailed((_) {
      if (myGen != _generation) return;
      _log('gen $myGen reconnect FAILED — giving up');
    });
    socket.onReconnectError((e) {
      if (myGen != _generation) return;
      _log('gen $myGen reconnect error: $e');
    });

    for (final name in _serverEvents) {
      socket.on(name, (data) {
        if (myGen != _generation) {
          _log('ignoring "$name" from stale gen $myGen (current gen $_generation)');
          return;
        }
        _log('gen $myGen recv "$name"');
        _events.add(SocketEvent(name, _coerce(data)));
      });
    }
    _log('listeners registered for ${_serverEvents.length} server events (incl. ride:offer)');

    _socket = socket;
    socket.connect();
  }

  /// Emit and await the server's ack `{ ok, ... }`.
  Future<Map<String, dynamic>> emitAck(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    final s = _socket;
    if (s == null) {
      return Future.value({'ok': false, 'error': 'NO_SOCKET', 'message': 'Not connected'});
    }
    final completer = Completer<Map<String, dynamic>>();
    s.emitWithAck(event, payload, ack: (res) {
      if (!completer.isCompleted) completer.complete(_coerce(res));
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () => {'ok': false, 'error': 'TIMEOUT', 'message': 'No response'},
    );
  }

  void emit(String event, Map<String, dynamic> payload) => _socket?.emit(event, payload);

  /// A connect / handshake error. If the server refused the token there is no
  /// point letting `socket_io_client` retry forever (it would, ~1e9 attempts) —
  /// stop, and let the auth layer force a re-login. Anything else is treated as
  /// a transient network blip and left to the normal reconnection loop.
  void _onConnectError(dynamic data) {
    _log('connect_error: $data');
    if (_isAuthError(data)) {
      _log('→ auth failure, stopping reconnect + forcing logout');
      _fatalAuth = true;
      disconnect();
      onAuthFailure?.call();
      return;
    }
    _setState(SocketConnState.connecting);
  }

  bool _isAuthError(dynamic data) {
    final msg = (data is Map
            ? (data['message'] ?? data['msg'] ?? data['data'] ?? data)
            : data)
        .toString()
        .toUpperCase();
    return _authErrorCodes.any(msg.contains);
  }

  void disconnect() {
    final s = _socket;
    _socket = null;
    _token = null;
    // Bump the generation so any handler still attached to `s` (a message
    // already in flight when dispose() is called) sees myGen != _generation
    // and drops itself instead of forwarding into the shared _events stream.
    _generation++;
    if (s != null) {
      _log('disconnect(): disposing old socket (sid=${s.id})');
      // Kill the reconnection manager before disposing so no stale timer can
      // fire another handshake with the old (now-dead) token.
      try {
        s.io.reconnection = false;
        s.io.skipReconnect = true;
      } catch (_) {/* best effort — dispose() still tears it down */}
      s.dispose();
    } else {
      _log('disconnect(): no socket was live');
    }
    _setState(SocketConnState.disconnected);
  }

  void dispose() {
    _connectivitySub?.cancel();
    disconnect();
    _events.close();
    _connState.close();
  }

  void _setState(SocketConnState s) {
    _state = s;
    if (!_connState.isClosed) _connState.add(s);
  }

  Map<String, dynamic> _coerce(dynamic data) =>
      data is Map ? data.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
}
