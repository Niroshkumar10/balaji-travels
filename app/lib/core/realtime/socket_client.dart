import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

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
  SocketClient();

  io.Socket? _socket;
  final _events = StreamController<SocketEvent>.broadcast();
  final _connState = StreamController<SocketConnState>.broadcast();
  SocketConnState _state = SocketConnState.disconnected;

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

  void connect(String token) {
    if (_socket != null) {
      _socket!.auth = {'token': token};
      if (!_socket!.connected) _socket!.connect();
      return;
    }
    _setState(SocketConnState.connecting);

    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setAuth({'token': token})
          .build(),
    );

    socket.onConnect((_) => _setState(SocketConnState.connected));
    socket.onDisconnect((_) => _setState(SocketConnState.disconnected));
    socket.onConnectError((_) => _setState(SocketConnState.connecting));
    socket.onReconnectAttempt((_) => _setState(SocketConnState.connecting));

    for (final name in _serverEvents) {
      socket.on(name, (data) {
        _events.add(SocketEvent(name, _coerce(data)));
      });
    }

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

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _setState(SocketConnState.disconnected);
  }

  void dispose() {
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
