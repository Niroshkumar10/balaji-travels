import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/debouncer.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../state/providers.dart';
import '../ride_session_controller.dart';

enum _Step { locations, fares, confirm }

class WhereToScreen extends ConsumerStatefulWidget {
  const WhereToScreen({super.key});
  @override
  ConsumerState<WhereToScreen> createState() => _WhereToScreenState();
}

class _WhereToScreenState extends ConsumerState<WhereToScreen> {
  _Step _step = _Step.locations;

  LatLngPoint? _pickup;
  LatLngPoint? _drop;

  RideEstimate? _estimate;
  FareOption? _selected;
  String _paymentMethod = 'cash';
  final _promoCtrl = TextEditingController();
  String? _promoApplied;
  double _promoDiscount = 0;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillPickup());
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
      builder: (_) => _PlaceSearchSheet(
        title: forPickup ? 'Set pickup' : 'Set destination',
        origin: _pickup,
      ),
    );
    if (picked != null) {
      setState(() => forPickup ? _pickup = picked : _drop = picked);
    }
  }

  Future<void> _loadFares() async {
    if (_pickup == null || _drop == null) return;
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LocationField(
          icon: Icons.trip_origin,
          iconColor: AppColors.brand,
          hint: 'Pickup location',
          value: _pickup?.addr,
          onTap: () => _pickPlace(forPickup: true),
        ),
        const SizedBox(height: 10),
        _LocationField(
          icon: Icons.place_rounded,
          iconColor: AppColors.danger,
          hint: 'Where to?',
          value: _drop?.addr,
          onTap: () => _pickPlace(forPickup: false),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'See fares',
          onPressed: (_pickup != null && _drop != null) ? _loadFares : null,
        ),
      ],
    );
  }

  Widget _faresStep() {
    final est = _estimate!;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: AppColors.canvas,
          child: Text(
            '${distance(est.route.distanceM)} · about ${duration(est.route.durationS)}',
            style: const TextStyle(color: AppColors.inkSoft),
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
        SectionCard(
          child: Column(
            children: [
              InfoRow('Pickup', _pickup?.addr ?? '—'),
              const Divider(),
              InfoRow('Destination', _drop?.addr ?? '—'),
              const Divider(),
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

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.icon,
    required this.iconColor,
    required this.hint,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String hint;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.isNotEmpty;
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
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
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

/// Autocomplete search sheet backed by the server-proxied Places API.
class _PlaceSearchSheet extends ConsumerStatefulWidget {
  const _PlaceSearchSheet({required this.title, this.origin});
  final String title;
  final LatLngPoint? origin;

  @override
  ConsumerState<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<_PlaceSearchSheet> {
  final _ctrl = TextEditingController();
  final _debouncer = Debouncer();
  List<PlacePrediction> _results = [];
  bool _loading = false;

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
      setState(() {
        _loading = false;
        _results = res.valueOrNull ?? [];
      });
    });
  }

  Future<void> _choose(PlacePrediction p) async {
    if (p.placeId == null) {
      Navigator.pop(context, LatLngPoint(lat: 0, lng: 0, addr: p.description));
      return;
    }
    final res = await ref.read(miscRepoProvider).placeDetails(p.placeId!);
    if (!mounted) return;
    res.when(
      ok: (loc) => Navigator.pop(
        context,
        LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? p.description),
      ),
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
              child: ListView.separated(
                controller: controller,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = _results[i];
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(p.mainText ?? p.description),
                    subtitle: p.secondaryText != null ? Text(p.secondaryText!) : null,
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
