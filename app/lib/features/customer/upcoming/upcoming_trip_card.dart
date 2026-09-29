import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/status_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

/// A future Rental/Trip booking card — adapted from RideHistoryTile
/// (history/ride_history_screen.dart), with the Case 1/2/3 status line
/// (ride.riderStageLabel, see core/models/ride.dart's RideAssignmentStage)
/// and driver/vehicle details revealed only once actually assigned.
class UpcomingTripCard extends StatelessWidget {
  const UpcomingTripCard({super.key, required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stage = ride.assignmentStage;
    final title = ride.rideType == 'rental'
        ? 'Rental${ride.rentalPackageHours != null ? ' · ${ride.rentalPackageHours} Hour${ride.rentalPackageHours == 1 ? '' : 's'}' : ''}'
        : ride.rideType == 'round_trip'
            ? 'Round Trip'
            : 'Trip';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: stage == RideAssignmentStage.live ? () => context.push('/c/ride/${ride.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(VehicleCategoryInfo.of(ride.vehicleCategory).emoji, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(dateTimeLabel(ride.scheduledAt ?? ride.requestedAt),
                            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(money(ride.finalFare ?? ride.estFare),
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ride.pickupAddr ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatusPill(ride.riderStageLabel, color: rideStatusColor(ride.status)),
                  ),
                  if (stage == RideAssignmentStage.live)
                    const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
                ],
              ),
              if (stage == RideAssignmentStage.reserved || stage == RideAssignmentStage.live) ...[
                const SizedBox(height: 10),
                _DriverStrip(ride: ride),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverStrip extends StatelessWidget {
  const _DriverStrip({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final driver = ride.driver;
    final vehicle = ride.vehicle;
    if (driver == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (vehicle != null)
                  Text(
                    '${vehicle.label} · ${plate(vehicle.plateNo)}',
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (driver.phoneMasked != null)
            const Icon(Icons.phone_rounded, size: 18, color: AppColors.inkSoft),
        ],
      ),
    );
  }
}
