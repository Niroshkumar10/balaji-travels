import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../core/payments/checkout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/vehicle_catalog.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../home/vehicle_picker_sheet.dart';
import '../ride_session_controller.dart';

/// Navigation payload for `/c/rental-packages`.
class RentalPackageArgs {
  const RentalPackageArgs({required this.pickup, required this.drop, required this.vehicle});
  final LatLngPoint pickup;
  final LatLngPoint drop;
  final VehiclePick vehicle;
}

/// Rental's fare step — package tiers (1hr/10km .. 10hr/100km) instead of
/// the generic bike/auto/hatchback/sedan/suv list Local/Outstation show,
/// since the vehicle was already chosen back on the home screen. Prices come
/// from the real backend (GET /rides/rental-packages — see rentalService.js)
/// for whichever of the 5 real categories the picked vehicle maps to (see
/// vehicle_catalog.dart's `rentalBookingCategory`) — same honest tradeoff
/// Outstation's fleet list already uses, not an invented per-vehicle number.
class RentalPackageScreen extends ConsumerStatefulWidget {
  const RentalPackageScreen({super.key, required this.args});
  final RentalPackageArgs args;

  @override
  ConsumerState<RentalPackageScreen> createState() => _RentalPackageScreenState();
}

class _RentalPackageScreenState extends ConsumerState<RentalPackageScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  bool _loading = true;
  String? _loadError;
  List<RentalPackage> _packages = const [];
  RentalPackage? _selected;
  String _paymentMethod = 'cash';
  DateTime? _scheduledAt; // null = now
  bool _busy = false;

  // The real driving route between pickup and drop, purely for the map line
  // — rental pricing is package-based (hours/km), not this route's distance,
  // so this comes from a separate /rides/estimate call just for the polyline.
  String? _polyline;

  String get _bookingCategory => rentalBookingCategory(widget.args.vehicle.category, widget.args.vehicle.variant);

  LatLng get _pickupLL => LatLng(widget.args.pickup.lat, widget.args.pickup.lng);
  LatLng get _dropLL => LatLng(widget.args.drop.lat, widget.args.drop.lng);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPackages();
      _loadRoute();
      _fitMap();
    });
  }

  Future<void> _loadRoute() async {
    final res = await ref
        .read(rideRepoProvider)
        .estimate(pickup: widget.args.pickup, drop: widget.args.drop);
    if (!mounted) return;
    res.when(
      ok: (est) => setState(() => _polyline = est.route.polyline),
      err: (_) {/* map still works with just the two markers */},
    );
  }

  @override
  void dispose() {
    Checkout.dispose();
    super.dispose();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await ref.read(rideRepoProvider).rentalPackages(vehicleCategory: _bookingCategory);
    if (!mounted) return;
    res.when(
      ok: (packages) => setState(() {
        _packages = packages;
        _selected = packages.isNotEmpty ? packages.first : null;
        _loading = false;
      }),
      err: (e) => setState(() {
        _loadError = e.message;
        _loading = false;
      }),
    );
  }

  void _fitMap() {
    final map = _mapKey.currentState;
    if (map == null) return;
    map.fitTo([_pickupLL, _dropLL], padding: 80);
  }

  Future<void> _pickSchedule() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RentalScheduleSheet(initial: _scheduledAt ?? DateTime.now().add(const Duration(hours: 1))),
    );
    if (picked != null) setState(() => _scheduledAt = picked);
  }

  Future<void> _confirmBooking() async {
    final pkg = _selected;
    if (pkg == null) return;
    if (_paymentMethod == 'upi') {
      await _confirmWithUpi(pkg);
    } else {
      await _createRide(pkg);
    }
  }

  Future<void> _createRide(RentalPackage pkg, {CheckoutResult? payment}) async {
    setState(() => _busy = true);
    final res = await ref.read(rideRepoProvider).create(
          pickup: widget.args.pickup,
          drop: widget.args.drop,
          vehicleCategory: _bookingCategory,
          rideType: 'rental',
          rentalPackageHours: pkg.hours,
          paymentMethod: _paymentMethod,
          scheduledAt: _scheduledAt,
          payment: payment,
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

  /// Same pre-payment pattern as where_to_screen.dart's Local UPI flow: quote
  /// + open Razorpay BEFORE any ride exists, only ever create the ride (and
  /// start dispatch/scheduling) from the success callback.
  Future<void> _confirmWithUpi(RentalPackage pkg) async {
    setState(() => _busy = true);
    final res = await ref.read(paymentRepoProvider).createPrebookOrder(
          pickup: widget.args.pickup,
          drop: widget.args.drop,
          vehicleCategory: _bookingCategory,
        );
    if (!mounted) return;
    res.when(
      ok: (order) {
        if (order.stub || order.keyId == null || !Checkout.isSupported) {
          _createRide(
            pkg,
            payment: CheckoutResult(
              orderId: order.orderId,
              paymentId: 'pay_sandbox_${DateTime.now().millisecondsSinceEpoch}',
              signature: '',
            ),
          );
          return;
        }
        Checkout.open(
          keyId: order.keyId!,
          orderId: order.orderId,
          amountPaise: order.amountPaise,
          name: 'Sri Balaji Travels',
          description: 'Rental booking',
          onSuccess: (r) => _createRide(pkg, payment: r),
          onError: (msg) {
            setState(() => _busy = false);
            if (mounted) showError(context, msg);
          },
        );
      },
      err: (e) {
        setState(() => _busy = false);
        showError(context, e.message);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.vehicle.label)),
      body: LoadingOverlay(
        busy: _busy,
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: MapView(
                key: _mapKey,
                initial: _pickupLL,
                markers: {
                  Marker(markerId: const MarkerId('p'), position: _pickupLL, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
                  Marker(markerId: const MarkerId('d'), position: _dropLL, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
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
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
                                const SizedBox(height: 12),
                                OutlinedButton(onPressed: _loadPackages, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          children: [
                            InfoRow('Pickup', widget.args.pickup.addr ?? '—'),
                            InfoRow('Drop', widget.args.drop.addr ?? '—'),
                            const SizedBox(height: 12),
                            const SectionHeader('Choose a package'),
                            ..._packages.map((pkg) {
                              final selected = _selected?.hours == pkg.hours;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: selected ? AppColors.primary.withValues(alpha: 0.07) : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
                                ),
                                child: ListTile(
                                  onTap: () => setState(() => _selected = pkg),
                                  leading: Icon(
                                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                    color: selected ? AppColors.primary : AppColors.inkSoft,
                                  ),
                                  title: Text(pkg.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  trailing: Text(money(pkg.fare), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _OptionBox(
                                    icon: Icons.payments_rounded,
                                    label: 'Cash',
                                    selected: _paymentMethod == 'cash',
                                    onTap: () => setState(() => _paymentMethod = 'cash'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _OptionBox(
                                    icon: Icons.event_rounded,
                                    label: _scheduledAt == null ? 'Schedule' : DateFormat('d MMM, h:mm a').format(_scheduledAt!),
                                    selected: _scheduledAt != null,
                                    onTap: _pickSchedule,
                                  ),
                                ),
                              ],
                            ),
                            if (_scheduledAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => setState(() => _scheduledAt = null),
                                    child: const Text('Book now instead'),
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: PrimaryButton(
                  label: _scheduledAt != null ? 'Confirm booking · ${DateFormat('d MMM, h:mm a').format(_scheduledAt!)}' : 'Confirm booking',
                  onPressed: _selected != null ? _confirmBooking : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionBox extends StatelessWidget {
  const _OptionBox({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.08) : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primary : AppColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.inkSoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: selected ? AppColors.primary : AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date+time picker for "Schedule the time and date" — same two-button
/// pattern as Outstation's schedule sheet (trip_review_screen.dart's
/// `_ScheduleSheet`), a fresh small widget here rather than extracting that
/// one (private to its file, and Outstation's own schedule button is
/// intentionally left as its existing cosmetic-only "coming soon" behavior —
/// only Rental's is wired to the real backend scheduling in this change).
class _RentalScheduleSheet extends StatefulWidget {
  const _RentalScheduleSheet({required this.initial});
  final DateTime initial;

  @override
  State<_RentalScheduleSheet> createState() => _RentalScheduleSheetState();
}

class _RentalScheduleSheetState extends State<_RentalScheduleSheet> {
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Schedule pickup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(DateFormat('d MMM yyyy').format(_value)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time_rounded, size: 16),
                    label: Text(DateFormat('h:mm a').format(_value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Set schedule', onPressed: () => Navigator.pop(context, _value)),
          ],
        ),
      ),
    );
  }
}
