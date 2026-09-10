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
    this.onCameraMoveStarted,
    this.onTap,
    this.myLocationEnabled = false,
    this.padding = const EdgeInsets.all(0),
  });

  final LatLng initial;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController)? onMapCreated;
  final void Function(CameraPosition)? onCameraMove;
  final VoidCallback? onCameraMoveStarted;
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

  /// A coordinate that could plausibly be a real place. Rejects out-of-range
  /// values and the ~5 km null-island patch around (0, 0) that unresolved
  /// geocodes collapse to — those would otherwise blow the camera bounds out
  /// to a whole-world view.
  static bool isRealLatLng(num lat, num lng) =>
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      !(lat.abs() < 0.05 && lng.abs() < 0.05);
}

class MapViewState extends State<MapView> {
  GoogleMapController? _controller;
  GoogleMapController? get controller => _controller;

  Future<void> fitTo(Iterable<LatLng> pts, {double padding = 60}) async {
    final list = pts
        .where((p) => MapView.isRealLatLng(p.latitude, p.longitude))
        .toList();
    if (_controller == null || list.isEmpty) return;
    if (list.length == 1) {
      await moveTo(list.first, zoom: 16);
      return;
    }
    final bounds = MapView.boundsOf(list);
    final spanLat = (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final spanLng =
        (bounds.northeast.longitude - bounds.southwest.longitude).abs();
    if (spanLat < 1e-6 && spanLng < 1e-6) {
      await moveTo(list.first, zoom: 16);
      return;
    }
    try {
      await _controller!
          .animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    } catch (_) {
      // newLatLngBounds throws if the platform view hasn't been measured yet
      // ("Map size can't be 0"). Give it a frame and try once more.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        await _controller
            ?.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
      } catch (_) {/* leave the camera where it is */}
    }
  }

  Future<void> moveTo(LatLng target, {double zoom = 15}) async {
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  /// Pan to a point WITHOUT changing zoom (used to follow a moving driver).
  Future<void> panTo(LatLng target) async {
    await _controller?.animateCamera(CameraUpdate.newLatLng(target));
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
      mapToolbarEnabled: false,
      buildingsEnabled: true,
      trafficEnabled: false,
      padding: widget.padding,
      onMapCreated: (c) {
        _controller = c;
        widget.onMapCreated?.call(c);
      },
      onCameraMove: widget.onCameraMove,
      onCameraMoveStarted: widget.onCameraMoveStarted,
      onTap: widget.onTap,
    );
  }
}
