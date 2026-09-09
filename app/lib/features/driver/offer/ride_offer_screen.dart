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

    return Scaffold(
      backgroundColor: AppColors.brand,
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
                      value: (offer.expiresInSec == 0 ? 1 : _left / offer.expiresInSec),
                      strokeWidth: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                  Text('$_left',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('New ride request',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
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
                          const Spacer(),
                          Text(
                            '~ ${money(offer.estFare)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _AddrRow(
                        icon: Icons.trip_origin,
                        color: AppColors.brand,
                        text: offer.pickup.addr ?? 'Pickup point',
                      ),
                      const SizedBox(height: 8),
                      _AddrRow(
                        icon: Icons.place_rounded,
                        color: AppColors.danger,
                        text: offer.drop.addr ?? 'Destination',
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Trip ${distance(offer.tripDistanceM)}',
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: () => _respond(false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.ink,
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
  const _AddrRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
