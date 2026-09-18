import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/debouncer.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../home/vehicle_picker_sheet.dart';
import '../ride_request/set_on_map_screen.dart';
import 'rental_package_screen.dart';

/// Navigation payload for `/c/rental-plan`.
class RentalPlanArgs {
  const RentalPlanArgs({required this.pickup, required this.vehicle});
  final LatLngPoint pickup;
  final VehiclePick vehicle;
}

/// Rental's own "Plan your ride" screen — pickup/drop entry, same inline
/// search-field pattern as Outstation's (OutstationPlanScreen) and Local's
/// (WhereToScreen), kept as its own screen rather than parameterizing either
/// of those: Rental's next step is a package list, not a fare-category list
/// or a One Way/Round Trip toggle, so sharing one of them would mean
/// branching their `_continue()` behavior for a case they don't otherwise
/// need to know about.
class RentalPlanScreen extends ConsumerStatefulWidget {
  const RentalPlanScreen({super.key, required this.args});
  final RentalPlanArgs args;

  @override
  ConsumerState<RentalPlanScreen> createState() => _RentalPlanScreenState();
}

class _RentalPlanScreenState extends ConsumerState<RentalPlanScreen> {
  late LatLngPoint _pickup = widget.args.pickup;
  LatLngPoint? _drop;
  final bool _busy = false;

  final _pickupCtrl = TextEditingController();
  final _pickupFocus = FocusNode();
  final _pickupDebouncer = Debouncer();
  List<PlacePrediction> _pickupResults = [];
  bool _pickupSearching = false;
  bool _pickupServiceDown = false;

  final _dropCtrl = TextEditingController();
  final _dropFocus = FocusNode();
  final _dropDebouncer = Debouncer();
  List<PlacePrediction> _dropResults = [];
  bool _dropSearching = false;
  bool _dropServiceDown = false;

  @override
  void initState() {
    super.initState();
    _pickupCtrl.text = _pickup.addr ?? '';
    _pickupFocus.addListener(() => setState(() {}));
    _dropFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _pickupFocus.dispose();
    _pickupDebouncer.dispose();
    _dropCtrl.dispose();
    _dropFocus.dispose();
    _dropDebouncer.dispose();
    super.dispose();
  }

  void _searchPickup(String q) {
    if (q.trim().length < 3) {
      setState(() {
        _pickupResults = [];
        _pickupSearching = false;
        _pickupServiceDown = false;
      });
      return;
    }
    setState(() => _pickupSearching = true);
    _pickupDebouncer.run(() async {
      final res = await ref.read(miscRepoProvider).autocomplete(q, lat: _pickup.lat, lng: _pickup.lng);
      if (!mounted) return;
      final all = res.valueOrNull ?? const <PlacePrediction>[];
      final usable = all.where((p) => (p.placeId ?? '').isNotEmpty).toList();
      setState(() {
        _pickupSearching = false;
        _pickupResults = usable;
        _pickupServiceDown = all.isNotEmpty && usable.isEmpty;
      });
    });
  }

  Future<void> _choosePickupResult(PlacePrediction p) async {
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
        _setPickup(LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? p.description));
      },
      err: (e) => showError(context, e.message),
    );
  }

  void _setPickup(LatLngPoint point) {
    setState(() {
      _pickup = point;
      _pickupCtrl.text = point.addr ?? '';
      _pickupResults = [];
      _pickupServiceDown = false;
    });
    _pickupFocus.unfocus();
  }

  void _searchDrop(String q) {
    if (q.trim().length < 3) {
      setState(() {
        _dropResults = [];
        _dropSearching = false;
        _dropServiceDown = false;
      });
      return;
    }
    setState(() => _dropSearching = true);
    _dropDebouncer.run(() async {
      final res = await ref.read(miscRepoProvider).autocomplete(q, lat: _pickup.lat, lng: _pickup.lng);
      if (!mounted) return;
      final all = res.valueOrNull ?? const <PlacePrediction>[];
      final usable = all.where((p) => (p.placeId ?? '').isNotEmpty).toList();
      setState(() {
        _dropSearching = false;
        _dropResults = usable;
        _dropServiceDown = all.isNotEmpty && usable.isEmpty;
      });
    });
  }

  Future<void> _chooseDropResult(PlacePrediction p) async {
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
        _setDrop(LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? p.description));
      },
      err: (e) => showError(context, e.message),
    );
  }

  void _setDrop(LatLngPoint point) {
    setState(() {
      _drop = point;
      _dropCtrl.text = point.addr ?? '';
      _dropResults = [];
      _dropServiceDown = false;
    });
    _dropFocus.unfocus();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLngPoint>(
      MaterialPageRoute(builder: (_) => SetOnMapScreen(initial: _pickup)),
    );
    if (picked != null) _setDrop(picked);
  }

  void _continue() {
    final drop = _drop;
    if (drop == null) return;
    context.push(
      '/c/rental-packages',
      extra: RentalPackageArgs(pickup: _pickup, drop: drop, vehicle: widget.args.vehicle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchingPickup = _pickupFocus.hasFocus && _pickupCtrl.text.trim().length >= 3;
    final searchingDrop = _dropFocus.hasFocus && _dropCtrl.text.trim().length >= 3;
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.vehicle.label)),
      body: LoadingOverlay(
        busy: _busy,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.trip_origin, color: AppColors.brand, size: 14),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _pickupCtrl,
                                  focusNode: _pickupFocus,
                                  onChanged: _searchPickup,
                                  onTapOutside: (_) {},
                                  style: const TextStyle(fontSize: 15),
                                  decoration: const InputDecoration(
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isCollapsed: true,
                                    hintText: 'Pickup location',
                                    hintStyle: TextStyle(color: AppColors.inkSoft, fontSize: 15),
                                  ),
                                ),
                              ),
                              if (_pickupSearching)
                                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else if (_pickupCtrl.text.isNotEmpty)
                                InkWell(
                                  onTap: () => setState(() {
                                    _pickupCtrl.clear();
                                    _pickupResults = [];
                                    _pickupServiceDown = false;
                                    _pickupFocus.unfocus();
                                  }),
                                  child: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkSoft),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, indent: 42),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.square_rounded, color: AppColors.danger, size: 14),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _dropCtrl,
                                  focusNode: _dropFocus,
                                  onChanged: _searchDrop,
                                  onTapOutside: (_) {},
                                  style: const TextStyle(fontSize: 15),
                                  decoration: const InputDecoration(
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isCollapsed: true,
                                    hintText: 'Where do you want to go?',
                                    hintStyle: TextStyle(color: AppColors.inkSoft, fontSize: 15),
                                  ),
                                ),
                              ),
                              if (_dropSearching)
                                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else if (_dropCtrl.text.isNotEmpty)
                                InkWell(
                                  onTap: () => setState(() {
                                    _dropCtrl.clear();
                                    _drop = null;
                                    _dropResults = [];
                                    _dropServiceDown = false;
                                    _dropFocus.unfocus();
                                  }),
                                  child: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkSoft),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (searchingPickup) ...[
                    if (_pickupServiceDown)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Place search is unavailable right now.\nCheck your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      )
                    else if (_pickupResults.isEmpty && !_pickupSearching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No matching places found.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
                      )
                    else
                      ..._pickupResults.map((p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.location_on_outlined, color: AppColors.inkSoft),
                            title: Text(p.mainText ?? p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: p.secondaryText != null ? Text(p.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                            onTap: () => _choosePickupResult(p),
                          )),
                  ] else if (searchingDrop) ...[
                    if (_dropServiceDown)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Place search is unavailable right now.\nCheck your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      )
                    else if (_dropResults.isEmpty && !_dropSearching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No matching places found.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
                      )
                    else
                      ..._dropResults.map((p) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.location_on_outlined, color: AppColors.inkSoft),
                            title: Text(p.mainText ?? p.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: p.secondaryText != null ? Text(p.secondaryText!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                            onTap: () => _chooseDropResult(p),
                          )),
                  ] else
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
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: PrimaryButton(label: 'See fares', onPressed: _drop != null ? _continue : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
