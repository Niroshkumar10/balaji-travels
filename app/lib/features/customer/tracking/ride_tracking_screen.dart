import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../ride_session_controller.dart';

class RideTrackingScreen extends ConsumerStatefulWidget {
  const RideTrackingScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideSessionProvider.notifier).attach(widget.rideId);
    });
  }

  void _handleStatus(RideStatus s) {
    if (s == RideStatus.driverCompleted || s == RideStatus.paymentPending) {
      context.go('/c/pay/${widget.rideId}');
    } else if (s == RideStatus.completed) {
      context.go('/c/rate/${widget.rideId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rideSessionProvider, (prev, next) {
      final s = next.ride?.status;
      if (s != null && prev?.ride?.status != s) _handleStatus(s);
    });

    final session = ref.watch(rideSessionProvider);
    final ride = session.ride;

    if (ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pickup = LatLng(ride.pickupLat, ride.pickupLng);
    final drop = LatLng(ride.dropLat, ride.dropLng);
    final driver = (session.driverLat != null && session.driverLng != null)
        ? LatLng(session.driverLat!, session.driverLng!)
        : null;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: drop,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          rotation: session.driverBearing ?? 0,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          infoWindow: const InfoWindow(title: 'Driver'),
        ),
    };

    final polylines = <Polyline>{};
    if (ride.polyline != null && ride.polyline!.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: MapView.decodePolyline(ride.polyline!),
        color: AppColors.brand,
        width: 5,
      ));
    }

    if (!_fitted) {
      _fitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapKey.currentState?.fitTo([pickup, drop, if (driver != null) driver]);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            key: _mapKey,
            initial: pickup,
            markers: markers,
            polylines: polylines,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _RoundBack(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Panel(ride: ride, etaSeconds: session.etaSeconds),
          ),
        ],
      ),
    );
  }
}

class _RoundBack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.go('/c/home'),
        child: const SizedBox(height: 44, width: 44, child: Icon(Icons.arrow_back_rounded)),
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.ride, this.etaSeconds});
  final Ride ride;
  final int? etaSeconds;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text('You may be charged a cancellation fee depending on timing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep ride')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel ride')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ref.read(rideSessionProvider.notifier).cancel(reason: 'customer_cancelled');
    if (context.mounted) {
      if (err != null) {
        showError(context, err);
      } else {
        context.go('/c/home');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ride.status;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (s) {
            RideStatus.requested || RideStatus.searchingDriver => _searching(context, ref),
            RideStatus.noDriversFound => _terminal(
                context,
                icon: Icons.search_off_rounded,
                title: 'No drivers found',
                message: 'Nobody was available nearby. Please try again.',
              ),
            RideStatus.customerCancelled ||
            RideStatus.driverCancelled ||
            RideStatus.systemCancelled =>
              _terminal(
                context,
                icon: Icons.cancel_rounded,
                title: 'Ride cancelled',
                message: ride.cancelReason ?? 'This ride was cancelled.',
              ),
            _ => _assigned(context, ref),
          },
        ),
      ),
    );
  }

  Widget _searching(BuildContext context, WidgetRef ref) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Finding you a driver…', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Matching you with a nearby driver',
              style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _cancel(context, ref),
            child: const Text('Cancel'),
          ),
        ],
      );

  Widget _terminal(BuildContext context,
      {required IconData icon, required String title, required String message}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: AppColors.inkSoft),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Book another ride', onPressed: () => context.go('/c/where-to')),
      ],
    );
  }

  Widget _assigned(BuildContext context, WidgetRef ref) {
    final d = ride.driver;
    final v = ride.vehicle;
    final s = ride.status;
    final headingToPickup =
        s == RideStatus.driverAssigned || s == RideStatus.driverArriving;
    final arrived = s == RideStatus.driverArrived;
    final onTrip = s == RideStatus.rideStarted || s == RideStatus.rideInProgress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                arrived
                    ? 'Your driver has arrived'
                    : onTrip
                        ? 'On the way to your destination'
                        : 'Driver is on the way',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (headingToPickup && etaSeconds != null)
              StatusPill('ETA ${eta(etaSeconds)}', color: AppColors.info),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const CircleAvatar(radius: 26, child: Icon(Icons.person)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d?.name ?? 'Driver',
                      style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
                      const SizedBox(width: 2),
                      Text((d?.rating ?? 0).toStringAsFixed(1),
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      if (v != null) ...[
                        const Text('  ·  ', style: TextStyle(color: AppColors.inkSoft)),
                        Text('${v.label} · ${plate(v.plateNo)}',
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (d?.phoneMasked != null)
              IconButton.filledTonal(
                onPressed: () => launchUrl(Uri.parse('tel:${d!.phoneMasked}')),
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
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text('Share this OTP with your driver',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  ride.otp!.split('').join(' '),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (onTrip) ...[
          const SizedBox(height: 12),
          InfoRow('Fare estimate', money(ride.amountDue), strong: true),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                ride.dropAddr ?? 'Destination',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.inkSoft),
              ),
            ),
            if (headingToPickup || arrived)
              TextButton(
                onPressed: () => _cancel(context, ref),
                child: const Text('Cancel', style: TextStyle(color: AppColors.danger)),
              ),
          ],
        ),
      ],
    );
  }
}
