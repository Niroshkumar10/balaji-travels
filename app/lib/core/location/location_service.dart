import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationPermissionResult {
  const LocationPermissionResult(this.granted, this.serviceEnabled, this.permanentlyDenied);
  final bool granted;
  final bool serviceEnabled;
  final bool permanentlyDenied;
}

/// Location access via geolocator. Kept UI-free so both the customer's
/// pick-a-point flow and the driver's continuous sharing use the same code.
class LocationService {
  Future<LocationPermissionResult> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationPermissionResult(false, false, false);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    final permanentlyDenied = perm == LocationPermission.deniedForever;
    final granted =
        perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    return LocationPermissionResult(granted, true, permanentlyDenied);
  }

  Future<Position?> current({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeout),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  /// Stream of positions for the driver's live sharing. `distanceFilter`
  /// throttles updates to meaningful movement (battery + network friendly).
  Stream<Position> stream({int distanceFilterM = 15}) => Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: distanceFilterM,
        ),
      );

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
