import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/geo_math.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_markers.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';

/// Navigation payload for `/c/trip-review`.
class TripReviewArgs {
  const TripReviewArgs({required this.pickup, required this.drop, required this.rideType});
  final LatLngPoint pickup;
  final LatLngPoint drop;

  /// 'outstation' or 'round_trip' — both real `rt_rides.ride_type` values.
  final String rideType;
}

/// One vehicle the fleet list offers. The backend only knows
/// bike/auto/hatchback/sedan/suv — there's no fare config or dispatch
/// category for "Urbania" or "Jaguar" yet — so [bookingCategory] maps each
/// display vehicle to the closest real category for the actual booking
/// (dispatch, driver matching) while the UI shows the real fleet name. The
/// fare itself is a distance-scaled estimate, not a backend quote, until
/// these categories get real fare configs.
class _Fleet {
  const _Fleet(this.name, this.seats, this.bookingCategory, this.baseFare, this.perKm);
  final String name;
  final int seats;
  final String bookingCategory;
  final double baseFare;
  final double perKm;

  double fareFor(double km) => baseFare + perKm * km;
}

const _fleet = [
  _Fleet('Urbania', 17, 'suv', 2500, 22),
  _Fleet('Tempo Traveller', 15, 'suv', 2000, 20),
  _Fleet('Toyota Fortuner', 6, 'suv', 3000, 26),
  _Fleet('Jaguar', 4, 'sedan', 6000, 45),
  _Fleet('Toyota Innova', 6, 'suv', 1200, 18),
  _Fleet('Swift Dzire', 4, 'hatchback', 800, 14),
];

class TripReviewScreen extends ConsumerStatefulWidget {
  const TripReviewScreen({super.key, required this.args});
  final TripReviewArgs args;

  @override
  ConsumerState<TripReviewScreen> createState() => _TripReviewScreenState();
}

class _TripReviewScreenState extends ConsumerState<TripReviewScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  bool _oneWay = true;
  DateTime _scheduledAt = DateTime.now();
  String _paymentMethod = 'cash';
  _Fleet _selected = _fleet.first;
  String? _polyline;
  bool _busy = false;

  // Straight-line distance is available instantly and synchronously, so the
  // page (and its fares) are never blocked on — or broken by — the routing
  // call below. That call, when it succeeds, only upgrades the number to a
  // real driving distance and draws the actual route line.
  late double _distanceKm = haversineMeters(
        widget.args.pickup.lat,
        widget.args.pickup.lng,
        widget.args.drop.lat,
        widget.args.drop.lng,
      ) /
      1000;

  String get _effectiveRideType => _oneWay ? 'outstation' : 'round_trip';

  LatLng get _pickupLL => LatLng(widget.args.pickup.lat, widget.args.pickup.lng);
  LatLng get _dropLL => LatLng(widget.args.drop.lat, widget.args.drop.lng);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
  }

  Future<void> _loadRoute() async {
    final res = await ref.read(rideRepoProvider).estimate(pickup: widget.args.pickup, drop: widget.args.drop);
    if (!mounted) return;
    res.when(
      ok: (est) => setState(() {
        _distanceKm = est.route.km;
        _polyline = est.route.polyline;
      }),
      // Real route unavailable — the page keeps working off the straight-line
      // distance already computed above. Nothing to show the rider; this
      // isn't a failure state, just a less precise number.
      err: (_) {},
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
  }

  void _fitMap() {
    final map = _mapKey.currentState;
    if (map == null) return;
    final pts = <LatLng>[
      if (MapView.isRealLatLng(_pickupLL.latitude, _pickupLL.longitude)) _pickupLL,
      if (MapView.isRealLatLng(_dropLL.latitude, _dropLL.longitude)) _dropLL,
    ];
    if (pts.isEmpty) return;
    pts.length == 1 ? map.moveTo(pts.first, zoom: 13) : map.fitTo(pts, padding: 80);
  }

  Future<void> _pickSchedule() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ScheduleSheet(initial: _scheduledAt),
    );
    if (picked != null) setState(() => _scheduledAt = picked);
  }

  void _pickPayment() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Payment method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.payments_rounded, color: AppColors.primary),
                title: const Text('Cash'),
                trailing: _paymentMethod == 'cash' ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () {
                  setState(() => _paymentMethod = 'cash');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_rounded, color: AppColors.primary),
                title: const Text('UPI'),
                trailing: _paymentMethod == 'upi' ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () {
                  setState(() => _paymentMethod = 'upi');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reviewBooking() async {
    final fare = _selected.fareFor(_distanceKm);
    final scheduledLater = _scheduledAt.difference(DateTime.now()).inMinutes.abs() > 5;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_oneWay ? 'Confirm one-way booking' : 'Confirm round trip booking',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              InfoRow('Pickup', widget.args.pickup.addr ?? '—'),
              InfoRow('Drop', widget.args.drop.addr ?? '—'),
              InfoRow('Vehicle', _selected.name),
              InfoRow('Fare estimate', money(fare)),
              InfoRow('Payment', _paymentMethod == 'cash' ? 'Cash' : 'UPI'),
              if (scheduledLater)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Scheduled pickups are coming soon — we\'ll dispatch a driver now instead of waiting for '
                      '${DateFormat('d MMM, h:mm a').format(_scheduledAt)}.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.secondaryDark),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Confirm booking', onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _create(fare);
  }

  Future<void> _create(double fare) async {
    setState(() => _busy = true);
    final res = await ref.read(rideRepoProvider).create(
          pickup: widget.args.pickup,
          drop: widget.args.drop,
          vehicleCategory: _selected.bookingCategory,
          rideType: _effectiveRideType,
          paymentMethod: _paymentMethod,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (ride) {
        ref.read(rideSessionProvider.notifier).attach(ride.id);
        context.go('/c/ride/${ride.id}');
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mk = MapMarkers.instance;
    return Scaffold(
      body: LoadingOverlay(
        busy: _busy,
        child: Stack(
          children: [
            Positioned.fill(
              child: MapView(
                key: _mapKey,
                initial: _pickupLL,
                markers: {
                  if (MapView.isRealLatLng(_pickupLL.latitude, _pickupLL.longitude))
                    Marker(markerId: const MarkerId('pickup'), position: _pickupLL, icon: mk.pickup, anchor: const Offset(0.5, 1)),
                  if (MapView.isRealLatLng(_dropLL.latitude, _dropLL.longitude))
                    Marker(markerId: const MarkerId('drop'), position: _dropLL, icon: mk.drop, anchor: const Offset(0.5, 1)),
                },
                polylines: {
                  if (_polyline != null && _polyline!.isNotEmpty)
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: MapView.decodePolyline(_polyline!),
                      color: AppColors.mapRoute,
                      width: 5,
                    ),
                },
                onMapCreated: (_) => WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap()),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/c/home'),
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.38,
              maxChildSize: 0.92,
              builder: (context, scrollController) => Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                elevation: 8,
                shadowColor: AppColors.cardShadow,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _TripTypeTab(
                          icon: Icons.north_east_rounded,
                          label: 'One Way',
                          selected: _oneWay,
                          onTap: () => setState(() => _oneWay = true),
                        ),
                        _TripTypeTab(
                          icon: Icons.sync_rounded,
                          label: 'Round Trip',
                          selected: !_oneWay,
                          onTap: () => setState(() => _oneWay = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickSchedule,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Booking ${_oneWay ? 'one-way' : 'round trip'} ride for',
                                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('d MMM yyyy, hh:mm a').format(_scheduledAt),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.canvas,
                              child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._fleet.map((f) {
                      final selected = _selected.name == f.name;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _selected = f),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: selected ? AppColors.cardSelectedBackground : null,
                              border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.directions_car_filled_rounded, size: 34, color: AppColors.textSecondary),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(f.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.person_rounded, size: 15, color: AppColors.inkSoft),
                                      Text('${f.seats}', style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Text(money(f.fareFor(_distanceKm)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickPayment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(_paymentMethod == 'cash' ? Icons.payments_rounded : Icons.qr_code_rounded, color: AppColors.primary),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('Personal', style: TextStyle(fontWeight: FontWeight.w700))),
                            Text(_paymentMethod == 'cash' ? 'Cash' : 'UPI', style: const TextStyle(color: AppColors.inkSoft)),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(label: 'Review Booking', onPressed: _reviewBooking),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripTypeTab extends StatelessWidget {
  const _TripTypeTab({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: selected ? AppColors.textPrimary : AppColors.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 3, width: 90, color: selected ? AppColors.primary : Colors.transparent),
        ],
      ),
    );
  }
}

/// Date + time picker sheet with its own Confirm button, opened from the
/// "Booking ... ride for ..." row.
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.initial});
  final DateTime initial;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late DateTime _value = widget.initial;

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _value,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d != null) setState(() => _value = DateTime(d.year, d.month, d.day, _value.hour, _value.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_value));
    if (t != null) setState(() => _value = DateTime(_value.year, _value.month, _value.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('When do you need the ride?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(DateFormat('d MMM yyyy').format(_value)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time_rounded, size: 18),
                    label: Text(DateFormat('hh:mm a').format(_value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Confirm', onPressed: () => Navigator.pop(context, _value)),
          ],
        ),
      ),
    );
  }
}
