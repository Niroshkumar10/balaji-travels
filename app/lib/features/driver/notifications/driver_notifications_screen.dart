import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/rt_app_bar.dart';
import '../../../state/providers.dart';
import '../../shared/notifications_list.dart';

class DriverNotificationsScreen extends ConsumerWidget {
  const DriverNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: RtAppBar(
        title: 'Notifications',
        fallbackRoute: '/d/dashboard',
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(miscRepoProvider).markAllNotificationsRead();
              ref.invalidate(notificationsProvider);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: const NotificationsListView(),
    );
  }
}
