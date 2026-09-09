import '../../../core/widgets/rt_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';

final _detailProvider =
    FutureProvider.autoDispose.family<(Ride?, List<Map<String, dynamic>>), int>((ref, id) async {
  final repo = ref.watch(rideRepoProvider);
  final ride = (await repo.get(id)).valueOrNull;
  final history = (await repo.history(id)).valueOrNull ?? const [];
  return (ride, history);
});

class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key, required this.rideId});
  final int rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_detailProvider(rideId));
    return Scaffold(
      appBar: const RtAppBar(title: 'Ride details', fallbackRoute: '/c/history'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
        data: (rec) {
          final ride = rec.$1;
          if (ride == null) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Ride not found');
          }
          final bd = ride.fareBreakdown;
          return ListView(
            children: [
              SizedBox(
                height: 220,
                child: MapView(
                  initial: LatLng(ride.pickupLat, ride.pickupLng),
                  markers: {
                    Marker(
                      markerId: const MarkerId('p'),
                      position: LatLng(ride.pickupLat, ride.pickupLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    ),
                    Marker(
                      markerId: const MarkerId('d'),
                      position: LatLng(ride.dropLat, ride.dropLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    ),
                  },
                  polylines: {
                    if (ride.polyline != null && ride.polyline!.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('r'),
                        points: MapView.decodePolyline(ride.polyline!),
                        color: AppColors.brand,
                        width: 4,
                      ),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(ride.ref, style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        StatusPill(ride.status.label, color: rideStatusColor(ride.status)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(dateTimeLabel(ride.requestedAt),
                        style: const TextStyle(color: AppColors.inkSoft)),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        children: [
                          InfoRow('Pickup', ride.pickupAddr ?? '—'),
                          const Divider(),
                          InfoRow('Destination', ride.dropAddr ?? '—'),
                          const Divider(),
                          InfoRow('Vehicle', VehicleCategoryInfo.of(ride.vehicleCategory).name),
                          InfoRow('Distance', distance(ride.distanceM)),
                          if (ride.driver != null) InfoRow('Driver', ride.driver!.name),
                          if (ride.vehicle != null)
                            InfoRow('Vehicle no.', plate(ride.vehicle!.plateNo)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Column(
                        children: [
                          if (bd['base'] != null) InfoRow('Base fare', money(bd['base'])),
                          if (bd['distance_charge'] != null)
                            InfoRow('Distance', money(bd['distance_charge'])),
                          if (bd['time_charge'] != null) InfoRow('Time', money(bd['time_charge'])),
                          if (bd['promo_discount'] != null && (bd['promo_discount'] as num) > 0)
                            InfoRow('Promo', '- ${money(bd['promo_discount'])}'),
                          const Divider(),
                          InfoRow('Total paid',
                              money(ride.finalFare ?? ride.estFare), strong: true),
                          InfoRow('Payment', (ride.paymentMethod ?? 'cash').toUpperCase()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Trip timeline', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...rec.$2.map((h) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.circle, size: 10, color: AppColors.brand),
                          title: Text('${h['from_status'] ?? '—'} → ${h['to_status']}'),
                          subtitle: Text('${h['actor']} · ${dateTimeLabel(asDate(h['created_at']))}'),
                        )),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
