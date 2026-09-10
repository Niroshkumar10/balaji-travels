import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Smoothly moves a value from its current position to each new target, so a
/// map marker glides instead of teleporting between GPS pings.
///
///   _anim = LatLngAnimator(vsync: this, onTick: () => setState(() {}));
///   ...
///   _anim.moveTo(newDriverLatLng);          // called on every ride:driver_location
///   Marker(position: _anim.value, rotation: _anim.bearing, ...)
class LatLngAnimator {
  LatLngAnimator({
    required TickerProvider vsync,
    required this.onTick,
    this.duration = const Duration(milliseconds: 900),
  }) : _ctrl = AnimationController(vsync: vsync, duration: duration) {
    _ctrl.addListener(_apply);
  }

  final VoidCallback onTick;
  final Duration duration;
  final AnimationController _ctrl;

  LatLng? _from;
  LatLng? _to;
  LatLng? _value;
  double _bearing = 0;

  LatLng? get value => _value ?? _to;
  double get bearing => _bearing;
  bool get hasValue => value != null;

  void moveTo(LatLng target, {double? bearing}) {
    if (_value == null) {
      _value = target;
      _to = target;
      if (bearing != null) _bearing = bearing;
      onTick();
      return;
    }
    _from = _value;
    _to = target;
    _bearing = bearing ?? _bearingBetween(_from!, target);
    _ctrl
      ..reset()
      ..forward();
  }

  void _apply() {
    final f = _from, t = _to;
    if (f == null || t == null) return;
    final k = Curves.easeInOut.transform(_ctrl.value);
    _value = LatLng(
      f.latitude + (t.latitude - f.latitude) * k,
      f.longitude + (t.longitude - f.longitude) * k,
    );
    onTick();
  }

  static double _bearingBetween(LatLng a, LatLng b) {
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final la1 = a.latitude * math.pi / 180;
    final la2 = b.latitude * math.pi / 180;
    final y = math.sin(dLon) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  void dispose() => _ctrl.dispose();
}
