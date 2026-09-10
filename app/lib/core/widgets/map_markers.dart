import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_colors.dart';

/// Renders crisp, correctly-sized marker bitmaps from Material icons so the map
/// looks like a real ride app (a car for the driver, teardrop pins for
/// pickup/drop) instead of the stock coloured balloons.
///
/// Sizes below are **logical points** — the canvas is rendered at the device
/// pixel ratio and tagged with `imagePixelRatio`/`width`/`height` so a pin is
/// ~34pt tall on every screen density (the earlier version baked raw pixels and
/// showed up huge on high-DPI phones).
class MapMarkers {
  MapMarkers._();
  static final MapMarkers instance = MapMarkers._();

  BitmapDescriptor? _car;
  BitmapDescriptor? _pickup;
  BitmapDescriptor? _drop;
  BitmapDescriptor? _me;
  Future<void>? _building;

  bool get ready => _car != null;

  BitmapDescriptor get car =>
      _car ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  BitmapDescriptor get pickup =>
      _pickup ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  BitmapDescriptor get drop =>
      _drop ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  BitmapDescriptor get me =>
      _me ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

  double get _dpr {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final r = views.isNotEmpty ? views.first.devicePixelRatio : 3.0;
    return r > 0 ? r : 3.0;
  }

  Future<void> ensureBuilt() {
    if (ready) return Future.value();
    return _building ??= _build();
  }

  Future<void> _build() async {
    final dpr = _dpr;
    _car = await _render(38, 38, dpr, _paintCar);
    _pickup =
        await _render(26, 34, dpr, (c, s) => _paintPin(c, s, AppColors.mapPickup));
    _drop =
        await _render(26, 34, dpr, (c, s) => _paintPin(c, s, AppColors.mapDrop));
    _me = await _render(22, 22, dpr, (c, s) => _paintDot(c, s, AppColors.mapUser));
  }

  /// White disc + coloured ring + taxi glyph — the moving driver.
  void _paintCar(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final rad = s.width / 2;
    c.drawCircle(
        ctr, rad, Paint()..color = Colors.black.withValues(alpha: 0.15));
    c.drawCircle(ctr, rad - 1.5, Paint()..color = Colors.white);
    c.drawCircle(
      ctr,
      rad - 1.5,
      Paint()
        ..color = AppColors.rideAssigned
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _glyph(c, Icons.local_taxi_rounded, s.width * 0.52, AppColors.rideAssigned,
        ctr);
  }

  /// Teardrop pin with a white centre — pickup / drop. Tip sits at (0.5, 1.0).
  void _paintPin(Canvas c, Size s, Color color) {
    final w = s.width;
    final headC = Offset(w / 2, w / 2);
    final headR = w / 2 - 1.5;
    final path = Path()
      ..addOval(Rect.fromCircle(center: headC, radius: headR))
      ..moveTo(w / 2 - w * 0.19, w / 2 + w * 0.22)
      ..lineTo(w / 2, s.height - 1)
      ..lineTo(w / 2 + w * 0.19, w / 2 + w * 0.22)
      ..close();
    c.drawShadow(path, Colors.black, 2, true);
    c.drawPath(
        path,
        Paint()
          ..color = color
          ..isAntiAlias = true);
    c.drawCircle(headC, headR * 0.42, Paint()..color = Colors.white);
  }

  /// "My location" dot with a soft halo.
  void _paintDot(Canvas c, Size s, Color color) {
    final ctr = Offset(s.width / 2, s.height / 2);
    c.drawCircle(
        ctr, s.width / 2, Paint()..color = color.withValues(alpha: 0.20));
    c.drawCircle(ctr, s.width * 0.26, Paint()..color = Colors.white);
    c.drawCircle(ctr, s.width * 0.19, Paint()..color = color);
  }

  void _glyph(Canvas c, IconData icon, double size, Color color, Offset center) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  Future<BitmapDescriptor> _render(
    double w,
    double h,
    double dpr,
    void Function(Canvas, Size) paint,
  ) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    paint(canvas, Size(w, h));
    final img = await rec
        .endRecording()
        .toImage((w * dpr).ceil(), (h * dpr).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      Uint8List.view(data!.buffer),
      imagePixelRatio: dpr,
      width: w,
      height: h,
    );
  }
}
