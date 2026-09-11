import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';

/// "Set location on map" — a fixed centre pin over a draggable map. The rider
/// pans the map instead of the pin; once the camera stops moving for a beat,
/// we reverse-geocode wherever the pin ends up. Pops the picked
/// [LatLngPoint], or null if backed out.
class SetOnMapScreen extends ConsumerStatefulWidget {
  const SetOnMapScreen({super.key, this.initial});
  final LatLngPoint? initial;

  @override
  ConsumerState<SetOnMapScreen> createState() => _SetOnMapScreenState();
}

class _SetOnMapScreenState extends ConsumerState<SetOnMapScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  late LatLng _center;
  bool _moving = false;
  bool _resolving = false;
  String? _addr;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _center = widget.initial != null
        ? LatLng(widget.initial!.lat, widget.initial!.lng)
        : const LatLng(12.9716, 77.5946);
    _resolve();
    if (widget.initial == null) _useCurrentLocation();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null || !mounted) return;
    _center = LatLng(pos.latitude, pos.longitude);
    _mapKey.currentState?.moveTo(_center, zoom: 16);
    _resolve();
  }

  // MapView doesn't expose a real "camera idle" callback, so we debounce off
  // onCameraMove instead: every move restarts a short timer, and the pin
  // settles once movement has actually stopped for a beat.
  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
    if (!_moving) setState(() => _moving = true);
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _moving = false);
      _resolve();
    });
  }

  Future<void> _resolve() async {
    setState(() => _resolving = true);
    final res = await ref
        .read(miscRepoProvider)
        .reverseGeocode(_center.latitude, _center.longitude);
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _addr = res.valueOrNull?.addr ??
          '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}';
    });
  }

  void _confirm() {
    Navigator.pop(
      context,
      LatLngPoint(lat: _center.latitude, lng: _center.longitude, addr: _addr),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          MapView(
            key: _mapKey,
            initial: _center,
            myLocationEnabled: true,
            onCameraMove: _onCameraMove,
          ),
          IgnorePointer(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.only(bottom: _moving ? 14 : 0),
              child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 46),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 12)],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place_rounded, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _resolving ? 'Locating…' : (_addr ?? ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Confirm this location',
                      busy: _resolving,
                      onPressed: _resolving ? null : _confirm,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
