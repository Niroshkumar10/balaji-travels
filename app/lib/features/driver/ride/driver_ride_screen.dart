import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_markers.dart';
import '../../../core/widgets/map_view.dart';
import '../../../core/widgets/otp_input.dart';
import '../driver_controller.dart';

class DriverRideScreen extends ConsumerStatefulWidget {
  const DriverRideScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<DriverRideScreen> createState() => _State();
}

class _State extends ConsumerState<DriverRideScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  String _otp = '';
  int _waitingSeconds = 0;
  Timer? _waitTimer;
  bool _pickupConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driverControllerProvider.notifier).loadActive();
    });
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  void _toggleWait() {
    if (_waitTimer != null) {
      _waitTimer!.cancel();
      _waitTimer = null;
      setState(() {});
    } else {
      _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _waitingSeconds++);
      });
    }
  }

  Future<void> _act(Future<String?> Function() action) async {
    final err = await action();
    if (mounted && err != null) showError(context, err);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      final was = prev?.ride?.status;
      final now = next.ride?.status;
      if (now == RideStatus.completed && was != RideStatus.completed) {
        context.push('/d/rate/${next.ride!.id}');
      }
    });
    final state = ref.watch(driverControllerProvider);
    final ride = state.ride;

    if (ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final s = ride.status;
    final toPickup = s == RideStatus.driverAssigned ||
        s == RideStatus.driverArriving ||
        s == RideStatus.driverArrived;
    final target = toPickup
        ? LatLng(ride.pickupLat, ride.pickupLng)
        : LatLng(ride.dropLat, ride.dropLng);
    final mk = MapMarkers.instance;
    final customer = state.hasCustomerLocation
        ? LatLng(state.customerLat!, state.customerLng!)
        : null;

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            key: _mapKey,
            initial: target,
            myLocationEnabled: true,
            markers: {
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(ride.pickupLat, ride.pickupLng),
                icon: mk.pickup,
                anchor: const Offset(0.5, 1),
              ),
              Marker(
                markerId: const MarkerId('drop'),
                position: LatLng(ride.dropLat, ride.dropLng),
                icon: mk.drop,
                anchor: const Offset(0.5, 1),
              ),
              if (toPickup && customer != null)
                Marker(
                  markerId: const MarkerId('customer'),
                  position: customer,
                  icon: mk.me,
                  anchor: const Offset(0.5, 0.5),
                ),
            },
            polylines: {
              if (ride.polyline != null && ride.polyline!.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: MapView.decodePolyline(ride.polyline!),
                  color: AppColors.mapRoute,
                  width: 5,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                ),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Round(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => context.go('/d/dashboard'),
                  ),
                  const Spacer(),
                  _Round(
                    icon: Icons.navigation_rounded,
                    onTap: () => launchUrl(Uri.parse(
                      'google.navigation:q=${target.latitude},${target.longitude}',
                    )),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Panel(
              ride: ride,
              busy: state.busy,
              otp: _otp,
              onOtpChanged: (v) => setState(() => _otp = v),
              waitingSeconds: _waitingSeconds,
              waiting: _waitTimer != null,
              onToggleWait: _toggleWait,
              pickupConfirmed: _pickupConfirmed,
              onConfirmPickup: () => setState(() => _pickupConfirmed = true),
              onStartNav: () => _act(ref.read(driverControllerProvider.notifier).startNavigation),
              onArrived: () => _act(ref.read(driverControllerProvider.notifier).markArrived),
              onStart: () => _act(() => ref.read(driverControllerProvider.notifier).startRide(_otp)),
              onCancel: () => _act(ref.read(driverControllerProvider.notifier).cancelRide),
              onComplete: () => _act(() => ref
                  .read(driverControllerProvider.notifier)
                  .completeRide((_waitingSeconds / 60).ceil())),
              onSettleCash: () => _act(ref.read(driverControllerProvider.notifier).settleCash),
              rider: state.rider,
              onDone: () {
                ref.read(driverControllerProvider.notifier).clearFinishedRide();
                context.go('/d/dashboard');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.ride,
    required this.busy,
    required this.otp,
    required this.onOtpChanged,
    required this.waitingSeconds,
    required this.waiting,
    required this.onToggleWait,
    required this.pickupConfirmed,
    required this.onConfirmPickup,
    required this.onStartNav,
    required this.onArrived,
    required this.onStart,
    required this.onCancel,
    required this.onComplete,
    required this.onSettleCash,
    required this.onDone,
    this.rider,
  });

  final Ride ride;
  final bool busy;
  final String otp;
  final ValueChanged<String> onOtpChanged;
  final int waitingSeconds;
  final bool waiting;
  final VoidCallback onToggleWait;
  final bool pickupConfirmed;
  final VoidCallback onConfirmPickup;
  final VoidCallback onStartNav;
  final VoidCallback onArrived;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onComplete;
  final VoidCallback onSettleCash;
  final VoidCallback onDone;
  final RiderInfo? rider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 16)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LoadingOverlay(busy: busy, child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (ride.status) {
      case RideStatus.driverAssigned:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rider != null) ...[_RiderRow(rider: rider!), const SizedBox(height: 14)],
            _header(context, 'Pick up ${_customerName()}'),
            const SizedBox(height: 4),
            Text(ride.pickupAddr ?? 'Pickup point', style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Start navigation to pickup', onPressed: onStartNav),
          ],
        );
      case RideStatus.driverArriving:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rider != null) ...[_RiderRow(rider: rider!), const SizedBox(height: 14)],
            _header(context, 'Heading to pickup'),
            const SizedBox(height: 4),
            Text(ride.pickupAddr ?? 'Pickup point', style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            PrimaryButton(label: 'I\'ve arrived', onPressed: onArrived),
          ],
        );
      case RideStatus.driverArrived:
        if (!pickupConfirmed) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rider != null) ...[_RiderRow(rider: rider!), const SizedBox(height: 14)],
              _header(context, 'Start trip?'),
              const SizedBox(height: 4),
              const Text(
                "Confirm that you've picked up the customer.",
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(height: 10),
              PrimaryButton(label: 'Start trip', onPressed: onConfirmPickup),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rider != null) ...[_RiderRow(rider: rider!), const SizedBox(height: 14)],
            _header(context, 'Ask the customer for the OTP'),
            const SizedBox(height: 14),
            OtpInput(length: 4, onChanged: onOtpChanged),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Start trip',
              onPressed: otp.length == 4 ? onStart : null,
            ),
          ],
        );
      case RideStatus.rideStarted:
      case RideStatus.rideInProgress:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, 'Trip in progress'),
            const SizedBox(height: 4),
            Text(ride.dropAddr ?? 'Destination',
                style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onToggleWait,
                  icon: Icon(waiting ? Icons.pause_rounded : Icons.timer_outlined, size: 18),
                  label: Text(waiting
                      ? 'Stop wait (${duration(waitingSeconds)})'
                      : 'Start waiting timer'),
                ),
                const Spacer(),
                if (ride.driver == null && ride.otp == null)
                  const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Complete trip', onPressed: onComplete),
          ],
        );
      case RideStatus.driverCompleted:
      case RideStatus.paymentPending:
        final isCash = (ride.paymentMethod ?? 'cash') == 'cash';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, 'Collect payment'),
            const SizedBox(height: 8),
            Text(money(ride.finalFare ?? ride.amountDue),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('${isCash ? 'Cash' : 'UPI'} payment',
                style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            if (isCash)
              PrimaryButton(label: 'Confirm cash received', onPressed: onSettleCash)
            else
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Waiting for customer to pay…'),
                ],
              ),
          ],
        );
      case RideStatus.completed:
        final b = ride.fareBreakdown;
        final base = (b['base'] as num?)?.toDouble();
        final distanceKm = (b['distance_km'] as num?)?.toDouble();
        final distanceCharge = (b['distance_charge'] as num?)?.toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 44, color: AppColors.success),
            const SizedBox(height: 8),
            Text('Trip complete', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (base != null || distanceKm != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    if (base != null) _FareRow('Base fare', money(base)),
                    if (distanceKm != null) _FareRow('Distance (${distanceKm.toStringAsFixed(1)} km)', money(distanceCharge ?? 0)),
                    const Divider(height: 20),
                    _FareRow('Total', money(ride.finalFare ?? ride.amountDue), bold: true),
                  ],
                ),
              )
            else
              Text('${money(ride.finalFare)} collected', style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Rate your rider', onPressed: () => context.push('/d/rate/${ride.id}')),
          ],
        );
      default:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ride.status.label),
            const SizedBox(height: 12),
            PrimaryButton(label: 'Back to dashboard', onPressed: onDone),
          ],
        );
    }
  }

  String _customerName() => 'the customer';

  Widget _header(BuildContext context, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

}

class _FareRow extends StatelessWidget {
  const _FareRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: bold ? style : style.copyWith(color: AppColors.inkSoft)),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _RiderRow extends StatelessWidget {
  const _RiderRow({required this.rider});
  final RiderInfo rider;

  void _unavailable(BuildContext context, String what) =>
      showError(context, "$what isn't available — the customer's number is kept private for safety.");

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(radius: 20, backgroundColor: AppColors.canvas, child: Icon(Icons.person, color: AppColors.inkSoft)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rider.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (rider.rating != null)
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.secondary),
                    const SizedBox(width: 2),
                    Text(rider.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                  ],
                ),
            ],
          ),
        ),
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _unavailable(context, 'Calling')),
        IconButton(icon: const Icon(Icons.chat_bubble_outline_rounded), onPressed: () => _unavailable(context, 'Chat')),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(height: 44, width: 44, child: Icon(icon)),
      ),
    );
  }
}
