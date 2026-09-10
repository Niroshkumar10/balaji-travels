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
              onStartNav: () => _act(ref.read(driverControllerProvider.notifier).startNavigation),
              onArrived: () => _act(ref.read(driverControllerProvider.notifier).markArrived),
              onStart: () => _act(() => ref.read(driverControllerProvider.notifier).startRide(_otp)),
              onComplete: () => _act(() => ref
                  .read(driverControllerProvider.notifier)
                  .completeRide((_waitingSeconds / 60).ceil())),
              onSettleCash: () => _act(ref.read(driverControllerProvider.notifier).settleCash),
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
    required this.onStartNav,
    required this.onArrived,
    required this.onStart,
    required this.onComplete,
    required this.onSettleCash,
    required this.onDone,
  });

  final Ride ride;
  final bool busy;
  final String otp;
  final ValueChanged<String> onOtpChanged;
  final int waitingSeconds;
  final bool waiting;
  final VoidCallback onToggleWait;
  final VoidCallback onStartNav;
  final VoidCallback onArrived;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onSettleCash;
  final VoidCallback onDone;

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
        return _stack(context, 'Pick up ${_customerName()}', ride.pickupAddr ?? 'Pickup point', [
          PrimaryButton(label: 'Start navigation to pickup', onPressed: onStartNav),
        ]);
      case RideStatus.driverArriving:
        return _stack(context, 'Heading to pickup', ride.pickupAddr ?? 'Pickup point', [
          PrimaryButton(label: 'I\'ve arrived', onPressed: onArrived),
        ]);
      case RideStatus.driverArrived:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            _header(context, 'On the way to destination'),
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 44, color: AppColors.success),
            const SizedBox(height: 8),
            Text('Trip complete', style: Theme.of(context).textTheme.titleLarge),
            Text('${money(ride.finalFare)} collected',
                style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Back to dashboard', onPressed: onDone),
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

  Widget _stack(BuildContext context, String title, String subtitle, List<Widget> actions) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, title),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppColors.inkSoft)),
        const SizedBox(height: 16),
        ...actions,
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
