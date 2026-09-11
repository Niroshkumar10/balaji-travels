import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/store/recent_search_store.dart';
import '../../../core/store/rider_contacts_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/debouncer.dart';
import '../../../core/util/default_suggestions.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_markers.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';
import 'set_on_map_screen.dart';

enum _Step { locations, fares, confirm }

/// Navigation payload for `/c/where-to` — lets the home screen jump straight
/// into a fare search with the destination already picked (tapping a
/// suggested place), open pre-scrolled to the "when" sheet (the "Pickup
/// later" shortcut), or carry a Rental vehicle choice made on the home
/// screen through to this step.
class WhereToArgs {
  const WhereToArgs({this.initialDrop, this.openLaterSheet = false, this.vehicleLabel});
  final LatLngPoint? initialDrop;
  final bool openLaterSheet;

  /// e.g. "Tempo Traveller · 15-seater Tempo Traveller" — set only when the
  /// rider came from the Rental vehicle picker, which has no backend fare
  /// engine yet. Non-null unlocks "Continue without drop".
  final String? vehicleLabel;
}

class WhereToScreen extends ConsumerStatefulWidget {
  const WhereToScreen({super.key, this.args});
  final WhereToArgs? args;

  @override
  ConsumerState<WhereToScreen> createState() => _WhereToScreenState();
}

class _WhereToScreenState extends ConsumerState<WhereToScreen> {
  _Step _step = _Step.locations;

  LatLngPoint? _pickup;
  LatLngPoint? _drop;
  bool _scheduleLater = false;
  String? _riderName; // null = booking for self ("Me")

  RideEstimate? _estimate;
  FareOption? _selected;
  String _paymentMethod = 'cash';
  final _promoCtrl = TextEditingController();
  String? _promoApplied;
  double _promoDiscount = 0;

  // "Suggestions near you" is the same fixed, instant list as the home
  // screen (see DefaultSuggestions) — no loading state needed for it.
  List<LatLngPoint> _recent = [];
  bool _recentLoading = true;
  final Set<String> _favoriting = {};
  final Set<String> _favorited = {};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _drop = widget.args?.initialDrop;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _prefillPickup();
      if (widget.args?.openLaterSheet == true && mounted) _pickWhen();
      _loadRecent();
    });
  }

  Future<void> _loadRecent() async {
    final recent = await RecentSearchStore.load();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _recentLoading = false;
    });
  }

  Future<void> _setDrop(LatLngPoint point) async {
    setState(() => _drop = point);
    RecentSearchStore.add(point);
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillPickup() async {
    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null || !mounted) return;
    final rev = await ref
        .read(miscRepoProvider)
        .reverseGeocode(pos.latitude, pos.longitude);
    rev.when(
      ok: (p) => setState(() => _pickup = p),
      err: (_) => setState(
        () => _pickup = LatLngPoint(lat: pos.latitude, lng: pos.longitude, addr: 'Current location'),
      ),
    );
  }

  Future<void> _pickPlace({required bool forPickup}) async {
    final picked = await showModalBottomSheet<LatLngPoint>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlaceSearchSheet(
        title: forPickup ? 'Set pickup' : 'Set destination',
        origin: _pickup,
      ),
    );
    if (picked == null) return;
    if (forPickup) {
      setState(() => _pickup = picked);
    } else {
      await _setDrop(picked);
    }
  }

  Future<void> _pickWhen() async {
    var later = _scheduleLater;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text('When do you need a ride?',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Divider(height: 1),
                _WhenTile(
                  icon: Icons.bolt_rounded,
                  title: 'Now',
                  subtitle: 'Request a ride, hop-in, and go',
                  selected: !later,
                  onTap: () => setSheet(() => later = false),
                ),
                const Divider(height: 1),
                _WhenTile(
                  icon: Icons.event_rounded,
                  title: 'Later',
                  subtitle: 'Reserve for extra peace of mind',
                  selected: later,
                  onTap: () => setSheet(() => later = true),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(ctx, later)),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _scheduleLater = result);
      if (result) {
        showOk(context, 'Scheduled rides are coming soon — booking for now instead.');
      }
    }
  }

  Future<void> _switchRider() async {
    // The sheet pops '' for "Me" and the contact's name otherwise — only on
    // "Done". A dismiss (back/tap-outside) pops null, which here means
    // "unchanged", not "switched to Me" — those are different things.
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SwitchRiderSheet(current: _riderName),
    );
    if (picked != null) setState(() => _riderName = picked.isEmpty ? null : picked);
  }

  Future<void> _pickSavedPlace() async {
    final res = await ref.read(miscRepoProvider).savedPlaces();
    final places = res.valueOrNull ?? const <SavedPlace>[];
    if (!mounted) return;
    if (places.isEmpty) {
      showOk(context, 'No saved places yet — add one from the star on a suggestion.');
      return;
    }
    final picked = await showModalBottomSheet<SavedPlace>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Saved places', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: places.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = places[i];
                    return ListTile(
                      leading: const Icon(Icons.bookmark_rounded, color: AppColors.primary),
                      title: Text(p.label),
                      subtitle: p.addr != null ? Text(p.addr!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await _setDrop(LatLngPoint(lat: picked.lat, lng: picked.lng, addr: picked.addr ?? picked.label));
    }
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLngPoint>(
      MaterialPageRoute(builder: (_) => SetOnMapScreen(initial: _drop ?? _pickup)),
    );
    if (picked != null) await _setDrop(picked);
  }

  Future<void> _chooseSuggestion(String label) async {
    final loc = await resolveSuggestion(ref, label, lat: _pickup?.lat, lng: _pickup?.lng);
    if (loc == null || !mounted) return;
    await _setDrop(LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? label));
  }

  Future<void> _favoritePoint(LatLngPoint p) async {
    final key = p.addr;
    if (key == null || _favoriting.contains(key) || _favorited.contains(key)) return;
    setState(() => _favoriting.add(key));
    final res = await ref.read(miscRepoProvider).addSavedPlace({
      'label': key,
      'lat': p.lat,
      'lng': p.lng,
      'addr': key,
    });
    if (!mounted) return;
    setState(() {
      _favoriting.remove(key);
      if (res.isOk) _favorited.add(key);
    });
    res.when(
      ok: (_) => showOk(context, 'Added to favorites'),
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _favoriteSuggestion(String label) async {
    if (_favoriting.contains(label) || _favorited.contains(label)) return;
    setState(() => _favoriting.add(label));
    final loc = await resolveSuggestion(ref, label, lat: _pickup?.lat, lng: _pickup?.lng);
    if (!mounted) return;
    if (loc == null) {
      setState(() => _favoriting.remove(label));
      showError(context, "Couldn't save that place. Try again.");
      return;
    }
    final res = await ref.read(miscRepoProvider).addSavedPlace({
      'label': label,
      'lat': loc.lat,
      'lng': loc.lng,
      'addr': loc.addr ?? label,
    });
    if (!mounted) return;
    setState(() {
      _favoriting.remove(label);
      if (res.isOk) _favorited.add(label);
    });
    res.when(
      ok: (_) => showOk(context, 'Added to favorites'),
      err: (e) => showError(context, e.message),
    );
  }

  void _swapPickupDrop() {
    if (_pickup == null && _drop == null) return;
    setState(() {
      final p = _pickup;
      _pickup = _drop;
      _drop = p;
    });
  }

  /// For Rental (no distance-based fare engine): capture the lead — pickup
  /// point and chosen vehicle — instead of running the local route/fare
  /// flow, which needs a real drop.
  void _continueWithoutDrop() {
    final vehicle = widget.args?.vehicleLabel;
    if (vehicle == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 40),
              const SizedBox(height: 14),
              const Text(
                "We've got your request",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Our team will call you to finalize the itinerary and fare for your $vehicle rental from ${_pickup?.addr ?? 'your pickup point'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) context.go('/c/home');
    });
  }

  bool get _placesReady =>
      _pickup != null &&
      _drop != null &&
      MapView.isRealLatLng(_pickup!.lat, _pickup!.lng) &&
      MapView.isRealLatLng(_drop!.lat, _drop!.lng);

  Future<void> _loadFares() async {
    if (_pickup == null || _drop == null) return;
    if (!_placesReady) {
      showError(context, 'Pick a valid pickup and destination from search first.');
      return;
    }
    setState(() => _busy = true);
    final res = await ref.read(rideRepoProvider).estimate(pickup: _pickup!, drop: _drop!);
    if (!mounted) return;
    setState(() => _busy = false);
    res.when(
      ok: (est) => setState(() {
        _estimate = est;
        _selected = est.options.isNotEmpty ? est.options.first : null;
        _step = _Step.fares;
      }),
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty || _selected == null) return;
    final res = await ref.read(miscRepoProvider).applyPromo(code, _selected!.fare);
    if (!mounted) return;
    res.when(
      ok: (j) => setState(() {
        _promoApplied = j['code']?.toString();
        _promoDiscount = (j['discount'] as num?)?.toDouble() ?? 0;
      }),
      err: (e) => showError(context, e.message),
    );
  }

  Future<void> _confirm() async {
    if (_pickup == null || _drop == null || _selected == null) return;
    if (!_placesReady) {
      showError(context, 'Pick a valid pickup and destination from search first.');
      return;
    }
    setState(() => _busy = true);
    final res = await ref.read(rideRepoProvider).create(
          pickup: _pickup!,
          drop: _drop!,
          vehicleCategory: _selected!.category,
          paymentMethod: _paymentMethod,
          promoCode: _promoApplied,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_step) {
          _Step.locations => 'Plan your ride',
          _Step.fares => 'Choose a ride',
          _Step.confirm => 'Confirm',
        }),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step != _Step.locations) {
              setState(() => _step = _Step.values[_step.index - 1]);
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/c/home');
            }
          },
        ),
      ),
      body: LoadingOverlay(
        busy: _busy,
        child: switch (_step) {
          _Step.locations => _locationsStep(),
          _Step.fares => _faresStep(),
          _Step.confirm => _confirmStep(),
        },
      ),
    );
  }

  Widget _locationsStep() {
    final vehicle = widget.args?.vehicleLabel;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _PillChip(
              icon: Icons.event_rounded,
              label: _scheduleLater ? 'Pickup later' : 'Pickup now',
              onTap: _pickWhen,
            ),
            const SizedBox(width: 10),
            _PillChip(
              icon: Icons.person_rounded,
              label: _riderName == null ? 'For me' : 'For $_riderName',
              onTap: _switchRider,
            ),
          ],
        ),
        if (vehicle != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_bus_filled_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(vehicle, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Pickup + drop as one connected card — a dot for pickup, a square
        // for drop, joined by a line. The swap button sits on that line and
        // flips the two.
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _LocationField(
                      icon: Icons.trip_origin,
                      iconColor: AppColors.brand,
                      hint: 'Pickup location',
                      value: _pickup?.addr,
                      onTap: () => _pickPlace(forPickup: true),
                      bordered: false,
                    ),
                    const Divider(height: 1, indent: 46),
                    _LocationField(
                      icon: Icons.square_rounded,
                      iconColor: AppColors.danger,
                      hint: 'Where to?',
                      value: _drop?.addr,
                      onTap: () => _pickPlace(forPickup: false),
                      bordered: false,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _RoundIconBtn(icon: Icons.swap_vert_rounded, onTap: _swapPickupDrop),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _PlanRow(icon: Icons.star_border_rounded, label: 'Saved places', onTap: _pickSavedPlace),
        const Divider(height: 1),
        _PlanRow(
          icon: Icons.public_rounded,
          label: 'Search in a different city',
          onTap: () => _pickPlace(forPickup: false),
        ),
        const Divider(height: 1),
        _PlanRow(icon: Icons.push_pin_outlined, label: 'Select on Map', onTap: _pickOnMap),

        if (!_recentLoading && _recent.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionHeader('Recent searches'),
          ..._recent.map((p) => _PlaceSuggestionRow(
                icon: Icons.history_rounded,
                title: p.addr ?? '${p.lat}, ${p.lng}',
                favorited: _favorited.contains(p.addr),
                busy: _favoriting.contains(p.addr),
                onTap: () => _setDrop(p),
                onFavorite: () => _favoritePoint(p),
              )),
        ],

        const SizedBox(height: 20),
        const SectionHeader('Suggestions near you'),
        ...DefaultSuggestions.nearYou.map((label) => _PlaceSuggestionRow(
              icon: Icons.place_rounded,
              title: label,
              favorited: _favorited.contains(label),
              busy: _favoriting.contains(label),
              onTap: () => _chooseSuggestion(label),
              onFavorite: () => _favoriteSuggestion(label),
            )),

        const SizedBox(height: 24),
        PrimaryButton(
          label: 'See fares',
          onPressed: _placesReady ? _loadFares : null,
        ),
        if (vehicle != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _pickup != null ? _continueWithoutDrop : null,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Continue Without Drop'),
          ),
        ],
      ],
    );
  }

  Widget _faresStep() {
    final est = _estimate!;
    return Column(
      children: [
        if (_placesReady)
          RoutePreviewMap(
            pickup: _pickup!,
            drop: _drop!,
            polyline: est.route.polyline,
            height: 190,
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppColors.canvas,
          child: Row(
            children: [
              const Icon(Icons.route_rounded, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Text(
                '${distance(est.route.distanceM)} · about ${duration(est.route.durationS)}',
                style: const TextStyle(color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: est.options.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final o = est.options[i];
              final info = VehicleCategoryInfo.of(o.category);
              final sel = _selected?.category == o.category;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selected = o),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? AppColors.brand : AppColors.line,
                      width: sel ? 2 : 1,
                    ),
                    color: sel ? AppColors.brand.withValues(alpha: 0.05) : null,
                  ),
                  child: Row(
                    children: [
                      Text(info.emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('${info.seats} seats',
                                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(money(o.fare),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              )),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PrimaryButton(
              label: 'Next',
              onPressed: _selected == null
                  ? null
                  : () => setState(() => _step = _Step.confirm),
            ),
          ),
        ),
      ],
    );
  }

  Widget _confirmStep() {
    final o = _selected!;
    final payable = (o.fare - _promoDiscount).clamp(0, double.infinity);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_placesReady) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: RoutePreviewMap(
              pickup: _pickup!,
              drop: _drop!,
              polyline: _estimate?.route.polyline,
              height: 170,
            ),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            children: [
              _AddrRow(
                icon: Icons.trip_origin,
                color: AppColors.brand,
                label: 'Pickup',
                value: _pickup?.addr,
              ),
              const Divider(height: 20),
              _AddrRow(
                icon: Icons.place_rounded,
                color: AppColors.danger,
                label: 'Destination',
                value: _drop?.addr,
              ),
              const Divider(height: 20),
              InfoRow('Vehicle', VehicleCategoryInfo.of(o.category).name),
              InfoRow('Fare estimate', money(o.fare)),
              if (_promoApplied != null)
                InfoRow('Promo ($_promoApplied)', '- ${money(_promoDiscount)}'),
              const Divider(),
              InfoRow('You pay (est.)', money(payable), strong: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Payment method', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            _PayChip(
              label: 'Cash',
              icon: Icons.payments_rounded,
              selected: _paymentMethod == 'cash',
              onTap: () => setState(() => _paymentMethod = 'cash'),
            ),
            const SizedBox(width: 10),
            _PayChip(
              label: 'UPI',
              icon: Icons.qr_code_rounded,
              selected: _paymentMethod == 'upi',
              onTap: () => setState(() => _paymentMethod = 'upi'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promoCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'Promo code'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _applyPromo,
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 52)),
              child: const Text('Apply'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Final fare is calculated by Sri Balaji Travels from the actual distance and time.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Confirm ride', onPressed: _confirm),
      ],
    );
  }
}

/// Label-over-address row used on the confirm card — long addresses wrap
/// cleanly instead of overflowing the row.
class _AddrRow extends StatelessWidget {
  const _AddrRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
                        color: AppColors.inkSoft, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  value ?? '—',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.icon,
    required this.iconColor,
    required this.hint,
    required this.onTap,
    this.value,
    this.bordered = true,
  });

  final IconData icon;
  final Color iconColor;
  final String hint;
  final String? value;
  final VoidCallback onTap;

  /// False when this field sits flush inside a shared connector card (the
  /// combined pickup/drop layout) instead of standing alone.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.isNotEmpty;
    final content = Row(
      children: [
        Icon(icon, color: iconColor, size: bordered ? 20 : 14),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            filled ? value! : hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled ? null : AppColors.inkSoft,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
    if (!bordered) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: content,
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: content,
      ),
    );
  }
}

/// Rounded outline chip used for "Pickup later" / "For me" above the
/// pickup/drop card.
class _PillChip extends StatelessWidget {
  const _PillChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain icon + label row used for the "Saved places" / "Search in a
/// different city" / "Set location on map" shortcuts.
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.inkSoft),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Small circular icon button used beside the pickup/drop card ("+" add-stop,
/// swap pickup/drop).
class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// One row in the "Recent searches" / "Suggestions near you" lists — a place
/// with a star/heart to save it as a favorite.
class _PlaceSuggestionRow extends StatelessWidget {
  const _PlaceSuggestionRow({
    required this.icon,
    required this.title,
    required this.favorited,
    required this.busy,
    required this.onTap,
    required this.onFavorite,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool favorited;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.inkSoft),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      onTap: onTap,
      trailing: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              icon: Icon(
                favorited ? Icons.star_rounded : Icons.star_border_rounded,
                color: favorited ? AppColors.secondary : AppColors.inkSoft,
              ),
              onPressed: onFavorite,
            ),
    );
  }
}

/// One row in the "When do you need a ride?" sheet.
class _WhenTile extends StatelessWidget {
  const _WhenTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Switch Rider" — pick who this ride is for. "Me" is always first and
/// can't be removed; "Add new contact" appends a local, on-device entry
/// (see RiderContactsStore — there's no backend field to send this to, so
/// it's a display-only label carried on the pill above, not sent with the
/// booking).
class _SwitchRiderSheet extends StatefulWidget {
  const _SwitchRiderSheet({required this.current});
  final String? current;

  @override
  State<_SwitchRiderSheet> createState() => _SwitchRiderSheetState();
}

class _SwitchRiderSheetState extends State<_SwitchRiderSheet> {
  List<RiderContact> _contacts = [];
  late String? _selected = widget.current;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    RiderContactsStore.load().then((c) {
      if (mounted) {
        setState(() {
          _contacts = c;
          _loading = false;
        });
      }
    });
  }

  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add new contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Name')),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Mobile number'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final contact = RiderContact(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim());
    await RiderContactsStore.add(contact);
    if (!mounted) return;
    setState(() {
      _contacts = [..._contacts, contact];
      _selected = contact.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            Text('Switch Rider', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: const Text('Me'),
              trailing: Icon(
                _selected == null ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: _selected == null ? AppColors.primary : AppColors.inkSoft,
              ),
              onTap: () => setState(() => _selected = null),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
            else
              for (final c in _contacts)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                  title: Text(c.name),
                  subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                  trailing: Icon(
                    _selected == c.name ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: _selected == c.name ? AppColors.primary : AppColors.inkSoft,
                  ),
                  onTap: () => setState(() => _selected = c.name),
                ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
              title: const Text('Add new contact', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              onTap: _addContact,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context, _selected ?? ''),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.brand : AppColors.inkSoft),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.brand : null,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small non-scrolling map that shows the pickup, drop and (if available) the
/// real route between them. Used on the fare + confirm steps so the rider sees
/// the trip before booking.
class RoutePreviewMap extends StatefulWidget {
  const RoutePreviewMap({
    super.key,
    required this.pickup,
    required this.drop,
    this.polyline,
    this.height = 190,
  });

  final LatLngPoint pickup;
  final LatLngPoint drop;
  final String? polyline;
  final double height;

  @override
  State<RoutePreviewMap> createState() => _RoutePreviewMapState();
}

class _RoutePreviewMapState extends State<RoutePreviewMap> {
  final _mapKey = GlobalKey<MapViewState>();

  LatLng get _p => LatLng(widget.pickup.lat, widget.pickup.lng);
  LatLng get _d => LatLng(widget.drop.lat, widget.drop.lng);
  bool get _pOk => MapView.isRealLatLng(widget.pickup.lat, widget.pickup.lng);
  bool get _dOk => MapView.isRealLatLng(widget.drop.lat, widget.drop.lng);

  void _fit() {
    final pts = <LatLng>[
      if (_pOk) _p,
      if (_dOk) _d,
    ];
    final poly = widget.polyline;
    if (poly != null && poly.isNotEmpty) {
      pts.addAll(MapView.decodePolyline(poly).where(
          (q) => MapView.isRealLatLng(q.latitude, q.longitude)));
    }
    final map = _mapKey.currentState;
    if (map == null || pts.isEmpty) return;
    pts.length == 1 ? map.moveTo(pts.first, zoom: 15) : map.fitTo(pts, padding: 44);
  }

  @override
  void didUpdateWidget(covariant RoutePreviewMap old) {
    super.didUpdateWidget(old);
    if (old.polyline != widget.polyline ||
        old.pickup.lat != widget.pickup.lat ||
        old.drop.lat != widget.drop.lat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mk = MapMarkers.instance;
    return SizedBox(
      height: widget.height,
      child: MapView(
        key: _mapKey,
        initial: _pOk ? _p : (_dOk ? _d : const LatLng(20.5937, 78.9629)),
        markers: {
          if (_pOk)
            Marker(
              markerId: const MarkerId('pickup'),
              position: _p,
              icon: mk.pickup,
              anchor: const Offset(0.5, 1),
            ),
          if (_dOk)
            Marker(
              markerId: const MarkerId('drop'),
              position: _d,
              icon: mk.drop,
              anchor: const Offset(0.5, 1),
            ),
        },
        polylines: {
          if (widget.polyline != null && widget.polyline!.isNotEmpty)
            Polyline(
              polylineId: const PolylineId('route'),
              points: MapView.decodePolyline(widget.polyline!),
              color: AppColors.mapRoute,
              width: 5,
            ),
        },
        onMapCreated: (_) =>
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit()),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppColors.inkSoft),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.inkSoft)),
            ],
          ),
        ),
      );
}

/// Autocomplete search sheet backed by the server-proxied Places API.
class PlaceSearchSheet extends ConsumerStatefulWidget {
  const PlaceSearchSheet({super.key, required this.title, this.origin});
  final String title;
  final LatLngPoint? origin;

  @override
  ConsumerState<PlaceSearchSheet> createState() => PlaceSearchSheetState();
}

class PlaceSearchSheetState extends ConsumerState<PlaceSearchSheet> {
  final _ctrl = TextEditingController();
  final _debouncer = Debouncer();
  List<PlacePrediction> _results = [];
  bool _loading = false;
  bool _serviceDown = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debouncer.run(() async {
      setState(() => _loading = true);
      final res = await ref.read(miscRepoProvider).autocomplete(
            q,
            lat: widget.origin?.lat,
            lng: widget.origin?.lng,
          );
      if (!mounted) return;
      final all = res.valueOrNull ?? const <PlacePrediction>[];
      // Only predictions we can actually resolve to coordinates are useful —
      // ones without a placeId (e.g. when the server has no maps key) would
      // otherwise be picked and collapse to (0, 0).
      final usable =
          all.where((p) => (p.placeId ?? '').isNotEmpty).toList();
      setState(() {
        _loading = false;
        _results = usable;
        _serviceDown = all.isNotEmpty && usable.isEmpty;
      });
    });
  }

  Future<void> _choose(PlacePrediction p) async {
    final id = p.placeId;
    if (id == null || id.isEmpty) {
      showError(context, 'Place search is unavailable right now. Try again shortly.');
      return;
    }
    final res = await ref.read(miscRepoProvider).placeDetails(id);
    if (!mounted) return;
    res.when(
      ok: (loc) {
        if (!MapView.isRealLatLng(loc.lat, loc.lng)) {
          showError(context, "Couldn't locate that place. Pick another result.");
          return;
        }
        Navigator.pop(
          context,
          LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? p.description),
        );
      },
      err: (e) => showError(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: widget.title,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _serviceDown
                  ? const _SearchHint(
                      icon: Icons.cloud_off_rounded,
                      text: 'Place search is unavailable right now.\n'
                          'Check your connection and try again.',
                    )
                  : ListView.separated(
                      controller: controller,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(p.mainText ?? p.description),
                          subtitle: p.secondaryText != null
                              ? Text(p.secondaryText!)
                              : null,
                          onTap: () => _choose(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
