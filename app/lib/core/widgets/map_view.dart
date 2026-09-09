import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Thin wrapper over GoogleMap that centralises the bits every ride screen
/// needs: a controller callback, fit-to-bounds, and decoding an encoded
/// polyline string into map points (so we don't pull in a polyline package).
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.initial,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onCameraMove,
    this.onTap,
    this.myLocationEnabled = false,
    this.padding = const EdgeInsets.all(0),
  });

  final LatLng initial;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController)? onMapCreated;
  final void Function(CameraPosition)? onCameraMove;
  final void Function(LatLng)? onTap;
  final bool myLocationEnabled;
  final EdgeInsets padding;

  @override
  State<MapView> createState() => MapViewState();

  /// Decode a Google encoded polyline.
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  static LatLngBounds boundsOf(Iterable<LatLng> pts) {
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    return LatLngBounds(
      southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
      northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
    );
  }
}

class MapViewState extends State<MapView> {
  GoogleMapController? _controller;

  Future<void> fitTo(Iterable<LatLng> pts, {double padding = 60}) async {
    if (_controller == null || pts.length < 2) return;
    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(MapView.boundsOf(pts), padding),
    );
  }

  Future<void> moveTo(LatLng target, {double zoom = 15}) async {
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: widget.initial, zoom: 15),
      markers: widget.markers,
      polylines: widget.polylines,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      padding: widget.padding,
      onMapCreated: (c) {
        _controller = c;
        widget.onMapCreated?.call(c);
      },
      onCameraMove: widget.onCameraMove,
      onTap: widget.onTap,
    );
  }
}
