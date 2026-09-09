import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/lat_lng_animator.dart';
import '../../../core/widgets/map_markers.dart';
import '../../../core/widgets/map_view.dart';
import '../ride_session_controller.dart';

/// Live ride tracking — real map, real route, real-time driver marker.
class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen>
    with TickerProviderStateMixin {
  final _mapKey = GlobalKey<MapViewState>();
  late final LatLngAnimator _driver;
  bool _followDriver = true;
  bool _initialFramed = false;
  DateTime _lastProgrammaticMove = DateTime.fromMillisecondsSinceEpoch(0);
  RideStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _driver = LatLngAnimator(
      vsync: this,
      onTick: () {
        if (mounted) setState(() {});
      },
    );
    MapMarkers.instance.ensureBuilt().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideSessionProvider.notifier).attach(widget.rideId);
    });
  }

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  bool _isMoving(RideStatus s) =>
      s == RideStatus.driverAssigned ||
      s == RideStatus.driverArriving ||
      s == RideStatus.rideStarted ||
      s == RideStatus.rideInProgress;

  void _onStatusChanged(RideStatus s) {
    if (s == RideStatus.driverCompleted || s == RideStatus.paymentPending) {
      context.go('/c/pay/${widget.rideId}');
    } else if (s == RideStatus.completed) {
      context.go('/c/rate/${widget.rideId}');
    }
  }

  /// Re-frame the camera to what matters for the current phase.
  void _reframe(Ride ride) {
    final map = _mapKey.currentState;
    if (map == null) return;
    _lastProgrammaticMove = DateTime.now();
    final pickup = LatLng(ride.pickupLat, ride.pickupLng);
    final drop = LatLng(ride.dropLat, ride.dropLng);
    final driver = _driver.value;

    switch (ride.status) {
      case RideStatus.driverAssigned:
      case RideStatus.driverArriving:
        map.fitTo(driver != null ? [driver, pickup] : [pickup, drop], padding: 90);
      case RideStatus.driverArrived:
        map.moveTo(pickup, zoom: 16.5);
      case RideStatus.rideStarted:
      case RideStatus.rideInProgress:
        map.fitTo(driver != null ? [driver, drop] : [pickup, drop], padding: 90);
      default:
        map.fitTo([pickup, drop]);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rideSessionProvider, (prev, next) {
      final ride = next.ride;
      if (ride == null) return;

      if (next.driverLat != null && next.driverLng != null) {
        _driver.moveTo(
          LatLng(next.driverLat!, next.driverLng!),
          bearing: next.driverBearing,
        );
        if (_followDriver && _isMoving(ride.status)) _reframe(ride);
      }

      if (ride.status != _lastStatus) {
        _lastStatus = ride.status;
        _onStatusChanged(ride.status);
        _followDriver = true;
        _reframe(ride);
      }
    });

    // Feed the customer's live position to the driver while they're en route.
    ref.listen(positionStreamProvider, (prev, next) {
      final pos = next.valueOrNull;
      final s = ref.read(rideSessionProvider).ride?.status;
      if (pos != null &&
          (s == RideStatus.driverAssigned || s == RideStatus.driverArriving)) {
        ref
            .read(rideSessionProvider.notifier)
            .pushMyLocation(pos.latitude, pos.longitude);
      }
    });

    final session = ref.watch(rideSessionProvider);
    final ride = session.ride;

    if (ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pickup = LatLng(ride.pickupLat, ride.pickupLng);
    final drop = LatLng(ride.dropLat, ride.dropLng);
    final mk = MapMarkers.instance;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: mk.pickup,
        anchor: const Offset(0.5, 1),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: drop,
        icon: mk.drop,
        anchor: const Offset(0.5, 1),
      ),
      if (_driver.hasValue)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driver.value!,
          icon: mk.car,
          rotation: _driver.bearing,
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
    };

    final polylines = <Polyline>{
      if (ride.polyline != null && ride.polyline!.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('route'),
          points: MapView.decodePolyline(ride.polyline!),
          color: AppColors.mapRoute,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    if (!_initialFramed) {
      _initialFramed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reframe(ride));
    }

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            key: _mapKey,
            initial: pickup,
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            padding: const EdgeInsets.only(top: 96, bottom: 280),
            onCameraMoveStarted: () {
              // A move we didn't trigger ⇒ user panned ⇒ stop following.
              if (DateTime.now()
                      .difference(_lastProgrammaticMove)
                      .inMilliseconds >
                  700) {
                _followDriver = false;
              }
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: _RoundBtn(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.go('/c/home'),
                ),
              ),
            ),
          ),
          if (session.hasDriverLocation && !_followDriver)
            Positioned(
              right: 16,
              bottom: 292,
              child: _RoundBtn(
                icon: Icons.navigation_rounded,
                onTap: () {
                  setState(() => _followDriver = true);
                  _reframe(ride);
                },
              ),
            ),
          if (session.hasDriverLocation && session.driverLocationStale)
            const SafeArea(
              child: Align(
                  alignment: Alignment.topCenter, child: _StaleBanner()),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Panel(ride: ride, session: session),
          ),
        ],
      ),
    );
  }
}

// ── header pieces ───────────────────────────────────────────────────────────
class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).cardColor,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(height: 44, width: 44, child: Icon(icon)),
        ),
      );
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Reconnecting to driver…',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      );
}

// ── bottom panel ────────────────────────────────────────────────────────────
class _Panel extends ConsumerWidget {
  const _Panel({required this.ride, required this.session});
  final Ride ride;
  final RideSessionState session;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text('A cancellation fee may apply depending on timing.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep ride'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ref
        .read(rideSessionProvider.notifier)
        .cancel(reason: 'customer_cancelled');
    if (context.mounted) {
      err != null ? showError(context, err) : context.go('/c/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
          BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 20,
              offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: switch (ride.status) {
            RideStatus.requested ||
            RideStatus.searchingDriver =>
              _searching(context, ref),
            RideStatus.noDriversFound => _terminal(
                context,
                icon: Icons.search_off_rounded,
                title: 'No drivers found',
                message:
                    'No one was available nearby right now. Please try again.',
              ),
            RideStatus.customerCancelled ||
            RideStatus.driverCancelled ||
            RideStatus.systemCancelled =>
              _terminal(
                context,
                icon: Icons.cancel_rounded,
                title: ride.status == RideStatus.driverCancelled
                    ? 'Driver cancelled'
                    : 'Ride cancelled',
                message: ride.cancelReason ?? 'This ride was cancelled.',
              ),
            _ => _active(context, ref),
          },
        ),
      ),
    );
  }

  // searching -------------------------------------------------------------
  Widget _searching(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PulseDot(),
        const SizedBox(height: 14),
        Text('Finding you a driver',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${VehicleCategoryInfo.of(ride.vehicleCategory).name}  ·  ${distance(ride.distanceM)}  ·  ${money(ride.amountDue)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _cancel(context, ref),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  // terminal ------------------------------------------------------------
  Widget _terminal(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: AppColors.textTertiary),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: 'Book another ride',
            onPressed: () => context.go('/c/where-to'),
          ),
        ),
      ],
    );
  }

  // assigned / arriving / arrived / on-trip -----------------------------
  Widget _active(BuildContext context, WidgetRef ref) {
    final s = ride.status;
    final d = ride.driver;
    final v = ride.vehicle;
    final toPickup =
        s == RideStatus.driverAssigned || s == RideStatus.driverArriving;
    final arrived = s == RideStatus.driverArrived;
    final onTrip =
        s == RideStatus.rideStarted || s == RideStatus.rideInProgress;
    final etaS = session.etaSeconds;

    final headline = arrived
        ? 'Your driver has arrived'
        : onTrip
            ? 'On the way to your destination'
            : s == RideStatus.driverAssigned
                ? 'Driver assigned'
                : 'Driver is on the way';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(headline,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (!arrived && etaS != null)
              _EtaChip(seconds: etaS, toPickup: toPickup),
          ],
        ),
        const SizedBox(height: 10),
        _Stepper(status: s),
        const SizedBox(height: 14),
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d?.name ?? 'Driver',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.secondary),
                      Text(' ${(d?.rating ?? 0).toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      if (v != null &&
                          (v.label.isNotEmpty || v.plateNo.isNotEmpty)) ...[
                        const Text('   ·   ',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        Flexible(
                          child: Text(
                            [v.label, plate(v.plateNo)]
                                .where((e) => e.isNotEmpty)
                                .join('  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (d?.phoneMasked != null)
              IconButton.filledTonal(
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${d!.phoneMasked}')),
                icon: const Icon(Icons.call_rounded),
              ),
          ],
        ),
        if (!onTrip && ride.otp != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                const Text('Share this OTP with the driver to start',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  ride.otp!.split('').join('   '),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2),
                ),
              ],
            ),
          ),
        ],
        if (onTrip) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                  icon: Icons.route_rounded, label: distance(ride.distanceM)),
              const SizedBox(width: 12),
              _Metric(
                icon: Icons.schedule_rounded,
                label: etaS != null ? eta(etaS) : duration(ride.durationS),
              ),
              const Spacer(),
              Text(
                money(ride.amountDue),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(onTrip ? Icons.flag_rounded : Icons.my_location_rounded,
                size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                onTrip
                    ? (ride.dropAddr ?? 'Destination')
                    : (ride.pickupAddr ?? 'Pickup point'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            if (toPickup || arrived)
              TextButton(
                onPressed: () => _cancel(context, ref),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.error)),
              ),
          ],
        ),
      ],
    );
  }
}

// ── small widgets ───────────────────────────────────────────────────────────
class _EtaChip extends StatelessWidget {
  const _EtaChip({required this.seconds, required this.toPickup});
  final int seconds;
  final bool toPickup;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.rideAssigned.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(eta(seconds),
              style: const TextStyle(
                  color: AppColors.rideAssigned,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          Text(toPickup ? 'to pickup' : 'to drop',
              style: const TextStyle(
                  color: AppColors.rideAssigned, fontSize: 9.5)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.status});
  final RideStatus status;

  int get _index => switch (status) {
        RideStatus.driverAssigned || RideStatus.driverArriving => 0,
        RideStatus.driverArrived => 1,
        RideStatus.rideStarted || RideStatus.rideInProgress => 2,
        _ => 3,
      };

  @override
  Widget build(BuildContext context) {
    const steps = 4;
    return Row(
      children: List.generate(steps * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < _index;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: done ? AppColors.primary : AppColors.cardBorder,
            ),
          );
        }
        final active = (i ~/ 2) <= _index;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primary : AppColors.cardBorder,
          ),
        );
      }),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: 48,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12 + 36 * t,
                height: 12 + 36 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: (1 - t) * 0.35),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary),
              ),
            ],
          );
        },
      ),
    );
  }
}
