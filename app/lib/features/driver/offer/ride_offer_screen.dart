import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../driver_controller.dart';

/// Incoming ride request, presented like Microlab's technician booking-request
/// overlay: a dimmed backdrop with a slide-up card (see the CustomTransitionPage
/// for '/d/offer/:id' in router.dart), a countdown ring that shifts
/// green -> amber -> red as the window runs out, and Accept weighted heavier
/// than Decline. If the offer is revoked (someone else took it / it timed out)
/// we pop automatically.
class RideOfferScreen extends ConsumerStatefulWidget {
  const RideOfferScreen({super.key, required this.rideId});
  final int rideId;

  @override
  ConsumerState<RideOfferScreen> createState() => _State();
}

class _State extends ConsumerState<RideOfferScreen> {
  Timer? _timer;
  int _left = 20;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
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
    if (_responding) return;
    setState(() => _responding = true);
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    final err = await ref
        .read(driverControllerProvider.notifier)
        .respondOffer(widget.rideId, accept);
    if (!mounted) return;
    if (accept && err == null) {
      context.go('/d/ride/${widget.rideId}');
    } else {
      setState(() => _responding = false);
      if (err != null) showError(context, err);
      if (context.canPop()) context.pop();
    }
  }

  /// green while there's plenty of time, amber past the halfway mark, red
  /// once it's about to expire — same urgency cue Microlab's ring uses.
  Color _ringColor(int total) {
    if (total <= 0) return AppColors.success;
    final frac = _left / total;
    if (frac > 0.5) return AppColors.success;
    if (frac > 0.25) return AppColors.secondary;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driverControllerProvider, (prev, next) {
      if (next.offer == null && (context.canPop())) context.pop();
    });

    final offer = ref.watch(driverControllerProvider.select((s) => s.offer));
    if (offer == null) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final total = offer.expiresInSec == 0 ? 20 : offer.expiresInSec;
    final ringValue = _left / total;
    final ringColor = _ringColor(total);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          SizedBox(height: safeTop + 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New ride request',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Respond before it expires',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: ringValue.clamp(0, 1),
                        strokeWidth: 4,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(ringColor),
                      ),
                      Text('$_left',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ringColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, safeBottom + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(VehicleCategoryInfo.of(offer.vehicleCategory).emoji, style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 10),
                        Text('${distance(offer.distanceToPickupM)} to pickup',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.canvas,
                          child: Icon(Icons.person, color: AppColors.inkSoft, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(offer.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (offer.customerPhoneMasked != null)
                                Text(offer.customerPhoneMasked!,
                                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _AddrRow(
                      icon: Icons.trip_origin,
                      color: AppColors.mapPickup,
                      label: 'PICKUP',
                      text: offer.pickup.addr ?? 'Pickup point',
                    ),
                    const SizedBox(height: 14),
                    _AddrRow(
                      icon: Icons.place_rounded,
                      color: AppColors.mapDrop,
                      label: 'DESTINATION',
                      text: offer.drop.addr ?? 'Destination',
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(child: _StatCol('Distance', distance(offer.tripDistanceM))),
                        Expanded(child: _StatCol('Payment', 'Cash / Online')),
                        Expanded(child: _StatCol('Estimated fare', money(offer.estFare))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _responding ? null : () => _respond(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 2x wider than Decline — Accept is the expected action.
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _responding ? null : () => _respond(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            child: _responding
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Accept'),
                          ),
                        ),
                      ],
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

class _StatCol extends StatelessWidget {
  const _StatCol(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ],
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
