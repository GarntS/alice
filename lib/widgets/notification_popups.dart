import 'package:flutter/material.dart';

import '../rust_gen/state.dart';
import 'panels/notification_card.dart';

const double notificationPopupWidth = 380;

class NotificationPopupStack extends StatelessWidget {
  const NotificationPopupStack({
    super.key,
    required this.notifications,
    required this.onDismissPopupRead,
    required this.onDismissNotification,
    required this.onMarkRead,
    required this.onInvokeAction,
  });

  final List<NotificationSnapshot> notifications;
  final void Function(int id) onDismissPopupRead;
  final void Function(int id) onDismissNotification;
  final void Function(int id) onMarkRead;
  final void Function(int id, String actionKey) onInvokeAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: notificationPopupWidth,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            clipBehavior: Clip.none,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final n = notifications[index];
              return Dismissible(
                key: ValueKey<int>(n.id),
                direction: DismissDirection.startToEnd,
                dismissThresholds: const {DismissDirection.startToEnd: 0.35},
                onDismissed: (_) => onDismissPopupRead(n.id),
                child: NotificationCard(
                  notification: n,
                  onBodyTap: () => onMarkRead(n.id),
                  onDismiss: () => onDismissNotification(n.id),
                  onInvokeAction: (key) => onInvokeAction(n.id, key),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
