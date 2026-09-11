import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/default_suggestions.dart';
import '../../../core/widgets/common_widgets.dart';
import '../ride_request/set_on_map_screen.dart';
import '../ride_request/where_to_screen.dart' show PlaceSearchSheet;
import 'trip_review_screen.dart';

/// Trip's own "Plan your ride" screen — reached by tapping the search box on
/// the home screen's Trip panel. Same pickup/drop shape as the Local flow,
/// but the destination list is the fixed popular-trip set instead of nearby
/// city suggestions, and picking a destination (by search, by tapping a
/// popular trip, or by map) goes straight to the trip review / fare screen
/// instead of the Local estimate flow.
class OutstationPlanScreen extends ConsumerStatefulWidget {
  const OutstationPlanScreen({super.key, required this.pickup});
  final LatLngPoint pickup;

  @override
  ConsumerState<OutstationPlanScreen> createState() => _OutstationPlanScreenState();
}

class _OutstationPlanScreenState extends ConsumerState<OutstationPlanScreen> {
  late LatLngPoint _pickup = widget.pickup;
  bool _busy = false;

  Future<void> _pickPickup() async {
    final picked = await showModalBottomSheet<LatLngPoint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(title: 'Set pickup', origin: _pickup),
    );
    if (picked != null) setState(() => _pickup = picked);
  }

  Future<void> _searchDrop() async {
    final picked = await showModalBottomSheet<LatLngPoint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(title: 'Where do you want to go?', origin: _pickup),
    );
    if (picked != null) _goToTripReview(picked);
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLngPoint>(
      MaterialPageRoute(builder: (_) => SetOnMapScreen(initial: _pickup)),
    );
    if (picked != null) _goToTripReview(picked);
  }

  Future<void> _chooseDestination(String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    final loc = await resolveSuggestion(ref, label, lat: _pickup.lat, lng: _pickup.lng);
    if (!mounted) return;
    setState(() => _busy = false);
    if (loc == null) {
      showError(context, "Couldn't locate that place. Try again.");
      return;
    }
    _goToTripReview(LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? label));
  }

  void _goToTripReview(LatLngPoint drop) {
    context.push(
      '/c/trip-review',
      extra: TripReviewArgs(pickup: _pickup, drop: drop, rideType: 'outstation'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan your ride')),
      body: LoadingOverlay(
        busy: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: _pickPickup,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.trip_origin, color: AppColors.brand, size: 14),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _pickup.addr ?? 'Pickup location',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 42),
                  InkWell(
                    onTap: _searchDrop,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.square_rounded, color: AppColors.danger, size: 14),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Where do you want to go?', style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickOnMap,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
                    SizedBox(width: 14),
                    Text('Select on Map', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader('Popular destinations'),
            ...DefaultSuggestions.outstation.map(
              (label) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.landscape_rounded, color: AppColors.inkSoft),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _chooseDestination(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
