import 'dart:async';

/// TEMPORARY in-memory diagnostic log for the driver-side Socket.IO problem
/// (driver shows online in the DB but the socket never registers in its
/// user:<id> room — see server dispatch logs: "totalSocketsConnected=N,
/// userRooms=user:2=N" with no user:<driverId> entry).
///
/// This does NOT create a second socket connection or a second logging
/// mechanism — every existing `[RT-SOCKET]`/`[RT-DRIVER]` print() call site
/// already in the codebase is routed into this same buffer (see
/// socket_client.dart's `_log`, driver_controller.dart's `_dlog`,
/// driver_shell.dart) so the on-screen panel and `adb logcat` always show
/// the identical sequence of events.
///
/// Memory-only, capped ring buffer — nothing persisted, nothing sent
/// anywhere. Intended to be removed once the underlying socket issue is
/// fixed and confirmed.
class SocketDiagLog {
  SocketDiagLog._();
  static final SocketDiagLog instance = SocketDiagLog._();

  static const _maxLines = 400;
  final List<String> _lines = [];
  final _changes = StreamController<void>.broadcast();

  /// Fires whenever a line is added or the log is cleared — the viewer
  /// listens to this to rebuild instead of polling.
  Stream<void> get onChange => _changes.stream;

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _lines.add('[$stamp] $message');
    if (_lines.length > _maxLines) _lines.removeAt(0);
    if (!_changes.isClosed) _changes.add(null);
  }

  void clear() {
    _lines.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Full buffer as plain text, newest last — what "Copy Logs" puts on the
  /// clipboard.
  String get asText => _lines.join('\n');
}
