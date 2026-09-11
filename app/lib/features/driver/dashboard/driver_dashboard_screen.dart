import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/map_view.dart';
import '../../../state/providers.dart';
import '../driver_controller.dart';
import '../earnings/earnings_controller.dart';

/// Home tab of the driver shell: live map + online/offline control, today's
/// snapshot, and the "resume active trip" / "finish setup" cards.
class DriverHomeTab extends ConsumerStatefulWidget {
  const DriverHomeTab({super.key});
  @override
  ConsumerState<DriverHomeTab> createState() => _DriverHomeTabState();
}

class _DriverHomeTabState extends ConsumerState<DriverHomeTab> {
  final _mapKey = GlobalKey<MapViewState>();
  LatLng _center = const LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    final pos = await ref.read(locationServiceProvider).current();
    if (pos == null || !mounted) return;
    setState(() => _center = LatLng(pos.latitude, pos.longitude));
    _mapKey.currentState?.moveTo(_center);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverControllerProvider);
    final profileAsync = ref.watch(driverProfileProvider);
    final earnings = ref.watch(todayEarningsProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      body: Stack(
        children: [
          MapView(key: _mapKey, initial: _center, myLocationEnabled: true),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      earnings.maybeWhen(
                        data: (s) => _Pill(
                          icon: Icons.account_balance_wallet_rounded,
                          text: 'Today ${money(s.net)}',
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      _RoundBtn(
                        icon: Icons.notifications_none_rounded,
                        onTap: () => context.push('/d/notifications'),
                      ),
                    ],
                  ),
                  if (AppConfig.isDev)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'build: $socketClientBuildMarker\n'
                        'session: role=${session.role?.name} userId=${session.userId} mobile=${session.mobile}\n'
                        'socket: ${state.socketState}   ·   last event: ${state.lastEvent ?? "(none)"}'
                        '${state.offer != null ? "   ·   OFFER #${state.offer!.rideId}" : ""}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: profileAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (p) {
                    if (p == null) return const SizedBox.shrink();
                    final blocked = !p.kycApproved ||
                        p.vehicles.every((v) => !v.isActive);
                    if (blocked) {
                      return _SetupCard(
                        reason: !p.kycApproved
                            ? (p.kycStatus == 'pending'
                                ? 'Your account is under review.'
                                : 'KYC not approved.')
                            : 'Add an active vehicle to start driving.',
                      );
                    }
                    if (state.ride != null && state.ride!.status.isActive) {
                      return _ResumeCard(
                        rideId: state.ride!.id,
                        label: state.ride!.status.label,
                      );
                    }
                    return _OnlineCard(
                      state: state,
                      trips: earnings.maybeWhen(
                          data: (s) => s.trips, orElse: () => null),
                      earned: earnings.maybeWhen(
                          data: (s) => s.net, orElse: () => null),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineCard extends ConsumerWidget {
  const _OnlineCard({required this.state, this.trips, this.earned});
  final DriverState state;
  final int? trips;
  final double? earned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = state.online;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  online
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  color: online ? AppColors.success : AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(online ? "You're online" : "You're offline",
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        online
                            ? 'Waiting for ride requests…'
                            : 'Go online to receive rides',
                        style: const TextStyle(
                            color: AppColors.inkSoft, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: online,
                  onChanged: state.busy
                      ? null
                      : (v) async {
                          final err = v
                              ? await ref
                                  .read(driverControllerProvider.notifier)
                                  .goOnline()
                              : await ref
                                  .read(driverControllerProvider.notifier)
                                  .goOffline();
                          if (err != null && context.mounted) {
                            showError(context, err);
                          }
                        },
                ),
              ],
            ),
            if (online) ...[
              const Divider(height: 24),
              Row(
                children: [
                  _MiniStat(label: 'Trips today', value: '${trips ?? 0}'),
                  const _MiniDivider(),
                  _MiniStat(label: 'Earned today', value: money(earned ?? 0)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    const TextStyle(color: AppColors.inkSoft, fontSize: 11.5)),
          ],
        ),
      );
}

class _MiniDivider extends StatelessWidget {
  const _MiniDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        color: AppColors.cardBorder,
      );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.rideId, required this.label});
  final int rideId;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.brand,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/d/ride/$rideId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.navigation_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active trip',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
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

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_rounded, size: 36, color: AppColors.info),
            const SizedBox(height: 8),
            Text(reason, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Open setup',
              onPressed: () => context.push('/d/setup'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: AppColors.cardShadow, blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
        ),
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(height: 44, width: 44, child: Icon(icon)),
      ),
    );
  }
}
