import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/providers.dart';

final notificationsProvider =
    FutureProvider.autoDispose<({List<NotificationItem> items, int unread})>((ref) async {
  final res = await ref.watch(miscRepoProvider).notifications(limit: 50);
  return res.valueOrNull ?? (items: <NotificationItem>[], unread: 0);
});

/// Shared notifications screen body for both roles.
class NotificationsListView extends ConsumerWidget {
  const NotificationsListView({super.key});

  IconData _iconFor(String type) => switch (type) {
        'driver_assigned' || 'ride_assigned' => Icons.directions_car_rounded,
        'driver_arrived' => Icons.pin_drop_rounded,
        'ride_started' => Icons.play_circle_rounded,
        'ride_completed' || 'payment_pending' => Icons.check_circle_rounded,
        'ride_cancelled' || 'no_drivers' => Icons.cancel_rounded,
        'ride_offer' => Icons.notifications_active_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', subtitle: '$e'),
      data: (data) {
        if (data.items.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'Nothing here yet',
            subtitle: 'Ride and payment updates will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(notificationsProvider.future),
          child: ListView.separated(
            itemCount: data.items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final n = data.items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: (n.isRead ? AppColors.inkSoft : AppColors.brand)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    _iconFor(n.type),
                    color: n.isRead ? AppColors.inkSoft : AppColors.brand,
                  ),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700),
                ),
                subtitle: n.body != null ? Text(n.body!) : null,
                trailing: Text(timeAgo(n.createdAt),
                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                onTap: () async {
                  if (!n.isRead) {
                    await ref.read(miscRepoProvider).markNotificationRead(n.id);
                    ref.invalidate(notificationsProvider);
                  }
                },
              );
            },
          ),
        );
      },
    );
  }
}
