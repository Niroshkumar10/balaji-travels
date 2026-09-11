import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/store/recent_search_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/default_suggestions.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../outstation/trip_review_screen.dart';
import '../ride_request/where_to_screen.dart';
import '../ride_session_controller.dart';
import 'vehicle_picker_sheet.dart';

enum _RideType { local, rental, outstation }

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});
  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  final _mapKey = GlobalKey<MapViewState>();
  LatLng _center = const LatLng(12.9716, 77.5946); // fallback until GPS fixes
  bool _hasFix = false;
  bool _follow = true;
  DateTime _lastProgrammaticMove = DateTime.fromMillisecondsSinceEpoch(0);

  _RideType _rideType = _RideType.local;

  // "Suggestions near you" is a fixed list shown instantly (see
  // DefaultSuggestions) — each label only resolves to real coordinates
  // lazily, on tap or favorite, so there's no loading spinner here at all.
  final Set<String> _favoriting = {};
  final Set<String> _favorited = {};

  // Trip destination list — shown inline in this same panel (no navigation)
  // once the Trip tab is selected.
  LatLngPoint? _outstationPickup;
  bool _resolvingOutstation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideSessionProvider.notifier).loadActive();
    });
  }

  void _recenter() {
    _follow = true;
    _lastProgrammaticMove = DateTime.now();
    _mapKey.currentState?.moveTo(_center, zoom: 16);
  }

  Future<void> _openSuggestion(String label) async {
    final loc = await resolveSuggestion(ref, label, lat: _center.latitude, lng: _center.longitude);
    if (loc == null || !mounted) return;
    final point = LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? label);
    RecentSearchStore.add(point);
    context.push('/c/where-to', extra: WhereToArgs(initialDrop: point));
  }

  Future<void> _favoriteSuggestion(String label) async {
    if (_favoriting.contains(label) || _favorited.contains(label)) return;
    setState(() => _favoriting.add(label));
    final loc = await resolveSuggestion(ref, label, lat: _center.latitude, lng: _center.longitude);
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

  void _openLocalSearch({bool later = false}) {
    context.push('/c/where-to', extra: WhereToArgs(openLaterSheet: later));
  }

  /// Rental: pick a vehicle (Urbania / Tempo Traveller / Car / Bus + seater),
  /// then land on the normal Plan-your-ride screen with that choice carried
  /// along as a banner — the rider can still search a real drop for a real
  /// fare, or use "Continue without drop" to leave it to the team.
  Future<void> _startRental() async {
    // Deliberately does NOT setState _rideType = rental — that state would
    // outlive the pushed screen (this widget isn't rebuilt when the rider
    // comes back), leaving the Rental pill "stuck" selected with the Local
    // search bar underneath it. That search bar bypasses the vehicle picker
    // entirely, which was the bug: coming back and tapping "I want to go"
    // skipped straight to pickup/drop. Every tap on Rental re-opens the
    // picker fresh instead.
    final pick = await showVehiclePickerSheet(context);
    if (pick == null || !mounted) return;
    context.push('/c/where-to', extra: WhereToArgs(vehicleLabel: pick.label));
  }

  /// Outstation: stays on this same screen — the panel below the tabs swaps
  /// to a destination search + fixed popular-trip list instead of navigating
  /// away. Resolves the rider's current position once, for use as pickup.
  Future<void> _startOutstation() async {
    setState(() => _rideType = _RideType.outstation);
    if (_outstationPickup != null) return;
    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null || !mounted) return;
    final rev = await ref.read(miscRepoProvider).reverseGeocode(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _outstationPickup = rev.valueOrNull ?? LatLngPoint(lat: pos.latitude, lng: pos.longitude, addr: 'Current location');
    });
  }

  Future<void> _chooseOutstation(String label) async {
    if (_outstationPickup == null || _resolvingOutstation) return;
    setState(() => _resolvingOutstation = true);
    final loc = await resolveSuggestion(ref, label, lat: _outstationPickup!.lat, lng: _outstationPickup!.lng);
    if (!mounted) return;
    setState(() => _resolvingOutstation = false);
    if (loc == null) {
      showError(context, "Couldn't locate that place. Try again.");
      return;
    }
    context.push(
      '/c/trip-review',
      extra: TripReviewArgs(
        pickup: _outstationPickup!,
        drop: LatLngPoint(lat: loc.lat, lng: loc.lng, addr: loc.addr ?? label),
        rideType: 'outstation',
      ),
    );
  }

  /// Local (and Rental, which has no distinct inline view) — search bar +
  /// "Pickup later" + the fixed nearby-suggestions list.
  Widget _localPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openLocalSearch(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    children: [
                      Icon(Icons.search_rounded, color: AppColors.inkSoft),
                      SizedBox(width: 10),
                      Text('I want to go...', style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openLocalSearch(later: true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_rounded, size: 18, color: AppColors.primary),
                      SizedBox(height: 2),
                      Text('Pickup\nlater', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, height: 1.1)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            itemCount: DefaultSuggestions.nearYou.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final label = DefaultSuggestions.nearYou[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_rounded, color: AppColors.inkSoft),
                title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _openSuggestion(label),
                trailing: _favoriting.contains(label)
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: Icon(
                          _favorited.contains(label) ? Icons.star_rounded : Icons.star_border_rounded,
                          color: _favorited.contains(label) ? AppColors.secondary : AppColors.inkSoft,
                        ),
                        onPressed: () => _favoriteSuggestion(label),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Outstation — shown right here in the same panel (no navigation): a
  /// search box plus the fixed list of popular outstation trips, filtered as
  /// the rider types. Tapping one goes straight to the trip review screen.
  Widget _outstationPanel() {
    return LoadingOverlay(
      busy: _resolvingOutstation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tappable, like Local's search bar — opens the full Plan-your-ride
          // screen (pickup/drop + Select on Map + popular destinations)
          // instead of filtering in place.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _outstationPickup == null
                ? null
                : context.push('/c/plan-trip', extra: _outstationPickup),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: AppColors.inkSoft),
                  SizedBox(width: 10),
                  Text('I want to go...', style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              itemCount: DefaultSuggestions.outstation.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final label = DefaultSuggestions.outstation[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.landscape_rounded, color: AppColors.inkSoft),
                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
                  onTap: () => _chooseOutstation(label),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(rideSessionProvider);
    final activeRide = session.ride;

    // Live GPS — recentre the camera as the rider moves (until they pan away).
    ref.listen(positionStreamProvider, (prev, next) {
      final p = next.valueOrNull;
      if (p == null || !mounted) return;
      _center = LatLng(p.latitude, p.longitude);
      final firstFix = !_hasFix;
      if (firstFix) setState(() => _hasFix = true);
      if (_follow || firstFix) {
        _lastProgrammaticMove = DateTime.now();
        _mapKey.currentState?.moveTo(_center, zoom: 16);
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const _CustomerDrawer(),
      body: Column(
        children: [
          const _TopBar(),
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: MapView(
                    key: _mapKey,
                    initial: _center,
                    myLocationEnabled: true,
                    onCameraMoveStarted: () {
                      if (DateTime.now().difference(_lastProgrammaticMove).inMilliseconds > 700) {
                        _follow = false;
                      }
                    },
                  ),
                ),
                if (activeRide != null && activeRide.status.isActive)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: _ResumeBanner(ride: activeRide),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _RoundBtn(
                    icon: Icons.my_location_rounded,
                    onTap: _recenter,
                    busy: !_hasFix,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            // Material (not a plain decorated Container) so the suggestion
            // list's ListTiles find it as their nearest Material ancestor and
            // paint ink splashes correctly instead of being swallowed by an
            // opaque box between them and the Scaffold's own Material.
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              elevation: 8,
              shadowColor: AppColors.cardShadow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _RideTypeTab(
                        icon: Icons.directions_car_filled_rounded,
                        label: 'Local',
                        selected: _rideType == _RideType.local,
                        onTap: () => setState(() => _rideType = _RideType.local),
                      ),
                      const SizedBox(width: 10),
                      // Rental/Outstation act immediately on tap — they don't
                      // use the search bar below (see _startRental/_startOutstation).
                      _RideTypeTab(
                        icon: Icons.schedule_rounded,
                        label: 'Rental',
                        selected: _rideType == _RideType.rental,
                        onTap: _startRental,
                      ),
                      const SizedBox(width: 10),
                      _RideTypeTab(
                        icon: Icons.alt_route_rounded,
                        label: 'Trip',
                        selected: _rideType == _RideType.outstation,
                        onTap: _startOutstation,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _rideType == _RideType.outstation ? _outstationPanel() : _localPanel(),
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

/// Hamburger (left) + centred brand wordmark, above the map.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Row(
          children: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            const Expanded(
              child: Text(
                'Sri Balaji',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 48), // balances the menu icon so the title stays centred
          ],
        ),
      ),
    );
  }
}

class _RideTypeTab extends StatelessWidget {
  const _RideTypeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Icon(icon, size: 26, color: selected ? AppColors.primary : AppColors.inkSoft),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.ride});
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/c/ride/${ride.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.directions_car_filled_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ride in progress',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(ride.status.label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.busy = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: 44,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _CustomerDrawer extends ConsumerWidget {
  const _CustomerDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Drawer(
      child: SafeArea(
        child: Column(
          // Without this, this Column centers its Padding child instead of
          // letting it fill the drawer's width — since that Padding's own
          // content (the icon + wordmark block) is only as wide as its text,
          // it was floating in the middle with dead space on both sides
          // (worse the wider the drawer, but present at any width, mobile or
          // desktop). Stretching here is what lets the inner
          // CrossAxisAlignment.start actually mean "flush against the left
          // edge of the drawer."
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon sits ABOVE the wordmark (not beside it) so it starts
                  // at the exact same left edge as the text below it, instead
                  // of pushing the wordmark right of the name/phone.
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'Sri Balaji ',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      TextSpan(
                        text: 'Travels',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      ),
                    ]),
                  ),
                  if (auth.name?.isNotEmpty == true || auth.mobile != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.name?.isNotEmpty == true ? auth.name! : 'Rider',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (auth.mobile != null) ...[
                      const SizedBox(height: 2),
                      Text('+91 ${auth.mobile}', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                    ],
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _item(context, Icons.receipt_long_rounded, 'Bookings', '/c/history'),
            _item(context, Icons.star_rounded, 'Favorites', '/c/saved-places', color: AppColors.secondary),
            _item(context, Icons.notifications_rounded, 'Notification', '/c/notifications'),
            _item(context, Icons.account_balance_wallet_rounded, 'Payment Methods', '/c/wallet'),
            _item(context, Icons.help_outline_rounded, 'Support', '/c/support'),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _item(context, Icons.local_offer_rounded, 'Offers', '/c/offers', color: AppColors.info),
            _item(context, Icons.person_rounded, 'Profile', '/c/profile'),
            const Spacer(),
            const Divider(height: 1),
            AppTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch to Driver',
              iconColor: AppColors.info,
              onTap: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/role');
              },
            ),
            AppTile(
              icon: Icons.logout_rounded,
              title: 'Log out',
              iconColor: AppColors.error,
              onTap: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/role');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, String route,
          {Color color = AppColors.primary}) =>
      AppTile(
        icon: icon,
        title: label,
        iconColor: color,
        onTap: () {
          // Capture the router BEFORE closing the drawer — popping the drawer
          // disposes this ListTile's context, and using it for push afterwards
          // is what made the pushed screen non-poppable ("back doesn't work").
          final router = GoRouter.of(context);
          Navigator.pop(context);
          router.push(route);
        },
      );
}
