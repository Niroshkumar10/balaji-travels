import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';

/// Full-screen incoming ride request with a countdown ring. If the offer is
/// revoked (someone else took it / it timed out) we pop automatically.
class RideOfferScreen extends ConsumerStatefulWidget {
  const RideOfferScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RideOfferScreen> createState() => _State();
}

class _State extends ConsumerState<RideOfferScreen> {
  Timer? _timer;
  int _left = 20;

  @override
  void initState() {
    super.initState();
    final offer = ref.read(driverControllerProvider).offer;
    _left = offer?.expiresInSec ?? 20;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 0) {
        t.cancel();
        if (mounted && context.canPop()) context.pop();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    _timer?.cancel();
    final err = await ref
        .read(driverControllerProvider.notifier)
        .respondOffer(widget.rideId, accept);
    if (!mounted) return;
    if (accept && err == null) {
      context.go('/d/ride/${widget.rideId}');
    } else {
      if (err != null) showError(context, err);
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.offer == null && (context.canPop())) context.pop();
    });

    final offer = ref.watch(driverControllerProvider.select((s) => s.offer));
    if (offer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ringValue = offer.expiresInSec == 0 ? 1.0 : _left / offer.expiresInSec;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 84,
                    width: 84,
                    child: CircularProgressIndicator(
                      value: ringValue,
                      strokeWidth: 6,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  Text('$_left',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              Text('New ride request',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(VehicleCategoryInfo.of(offer.vehicleCategory).emoji,
                              style: const TextStyle(fontSize: 26)),
                          const SizedBox(width: 10),
                          Text(
                            '${distance(offer.distanceToPickupM)} to pickup',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _AddrRow(
                        icon: Icons.trip_origin,
                        color: AppColors.mapPickup,
                        label: 'PICKUP LOCATION',
                        text: offer.pickup.addr ?? 'Pickup point',
                      ),
                      const SizedBox(height: 14),
                      _AddrRow(
                        icon: Icons.place_rounded,
                        color: AppColors.mapDrop,
                        label: 'DROP LOCATION',
                        text: offer.drop.addr ?? 'Destination',
                      ),
                      const Divider(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Text('Estimated fare',
                                style: TextStyle(color: AppColors.inkSoft)),
                            const Spacer(),
                            Text(
                              money(offer.estFare),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Trip distance ${distance(offer.tripDistanceM)}',
                            style: const TextStyle(
                                color: AppColors.inkSoft, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => _respond(false),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => _respond(true),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddrRow extends StatelessWidget {
  const _AddrRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
