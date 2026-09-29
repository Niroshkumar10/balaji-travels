import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/rt_app_bar.dart';
import '../driver_controller.dart';
import 'rental_trip_controller.dart';

/// A single Rental/Trip booking's details, with the three driver actions:
/// Accept / Decline while awaiting confirmation, or Start Navigation once
/// reserved. Start Navigation hands off into the existing DriverRideScreen
/// (/d/ride/:id) for everything after that — no second navigation/live-trip
/// UI is built here (see driver_ride_screen.dart's google.navigation: deep
/// link and OTP/complete flow, both reused unchanged).
class RentalTripDetailScreen extends ConsumerStatefulWidget {
  const RentalTripDetailScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RentalTripDetailScreen> createState() => _RentalTripDetailScreenState();
}

class _RentalTripDetailScreenState extends ConsumerState<RentalTripDetailScreen> {
  bool _busy = false;

  Ride? get _ride {
    final rides = ref.watch(rentalTripProvider);
    for (final r in rides) {
      if (r.id == widget.rideId) return r;
    }
    return null;
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final err = await ref.read(rentalTripProvider.notifier).accept(widget.rideId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showError(context, err);
    } else {
      showOk(context, 'Booking accepted — you’re reserved.');
    }
  }

  Future<void> _decline() async {
    final reason = await _askDeclineReason();
    if (reason == null) return; // user cancelled the sheet
    setState(() => _busy = true);
    final err = await ref.read(rentalTripProvider.notifier).decline(widget.rideId, reason: reason.isEmpty ? null : reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showError(context, err);
    } else {
      showOk(context, 'Booking declined.');
      context.pop();
    }
  }

  /// Returns the (possibly empty) decline reason, or null if the driver
  /// dismissed the sheet without confirming.
  Future<String?> _askDeclineReason() async {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Decline this booking?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('It will be offered to another driver.', style: TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Reason (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startNavigation() async {
    setState(() => _busy = true);
    final err = await ref.read(driverControllerProvider.notifier).startReservedNavigation(widget.rideId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showError(context, err);
      return;
    }
    ref.read(rentalTripProvider.notifier).refresh();
    context.push('/d/ride/${widget.rideId}');
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    return Scaffold(
      appBar: RtAppBar(
        title: ride?.rideType == 'rental' ? 'Rental Details' : 'Trip Details',
        fallbackRoute: '/d/rental-trip',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(rentalTripProvider.notifier).refresh(),
          ),
        ],
      ),
      body: ride == null
          ? const Center(child: CircularProgressIndicator())
          : LoadingOverlay(
              busy: _busy,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InfoRow('Pickup', ride.pickupAddr ?? '—'),
                          if (ride.serviceKind == 'trip') InfoRow('Destination', ride.dropAddr ?? '—'),
                          if (ride.rideType == 'rental' && ride.rentalPackageHours != null)
                            InfoRow('Duration', '${ride.rentalPackageHours} Hours'),
                          if (ride.rideType == 'round_trip') const InfoRow('Trip Type', 'Round Trip'),
                          InfoRow('Pickup Time', dateTimeLabel(ride.scheduledAt ?? ride.requestedAt)),
                          InfoRow('Fare', money(ride.finalFare ?? ride.estFare), strong: true),
                          InfoRow('Status', _statusLabel(ride)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._actions(ride),
                  ],
                ),
              ),
            ),
    );
  }

  String _statusLabel(Ride ride) => switch (ride.assignmentStage) {
        RideAssignmentStage.awaitingDriverConfirmation => 'Awaiting your confirmation',
        RideAssignmentStage.reserved => 'Reserved',
        RideAssignmentStage.live => 'On trip',
        _ => ride.status.label,
      };

  List<Widget> _actions(Ride ride) {
    switch (ride.assignmentStage) {
      case RideAssignmentStage.awaitingDriverConfirmation:
        return [
          PrimaryButton(label: 'Accept', icon: Icons.check_rounded, onPressed: _busy ? null : _accept),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _decline,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, minimumSize: const Size.fromHeight(48)),
            child: const Text('Decline'),
          ),
        ];
      case RideAssignmentStage.reserved:
        return [
          PrimaryButton(label: 'Start Navigation', icon: Icons.navigation_rounded, onPressed: _busy ? null : _startNavigation),
          const SizedBox(height: 8),
          const Text(
            'You can still take Local rides while reserved. Starting navigation marks you on this trip.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
        ];
      case RideAssignmentStage.live:
        return [
          PrimaryButton(label: 'Open Trip', icon: Icons.arrow_forward_rounded, onPressed: () => context.push('/d/ride/${ride.id}')),
        ];
      default:
        return const [];
    }
  }
}
