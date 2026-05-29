import 'package:flutter/material.dart';

import '../../rust_gen/state.dart';
import 'notification_card.dart';

class NotificationPanel extends StatefulWidget {
  const NotificationPanel({
    super.key,
    required this.notifications,
    required this.onDismissAll,
    required this.onDismissOne,
    required this.onMarkAllRead,
    required this.onInvokeAction,
  });

  final List<NotificationSnapshot> notifications;
  final VoidCallback onDismissAll;
  final void Function(int id) onDismissOne;
  final VoidCallback onMarkAllRead;
  final void Function(int id, String actionKey) onInvokeAction;

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  late final ScrollController _scrollController = ScrollController();
  final Set<int> _pendingDismissedIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMarkAllRead();
    });
  }

  @override
  void didUpdateWidget(NotificationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.notifications.map((n) => n.id).toSet();
    _pendingDismissedIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _dismissNotification(int id) {
    setState(() => _pendingDismissedIds.add(id));
    widget.onDismissOne(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = widget.notifications
        .where((n) => !_pendingDismissedIds.contains(n.id))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: sorted.length > 3,
      child: ListView(
        controller: _scrollController,
        clipBehavior: Clip.none,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Row(
            children: [
              Text(
                'Notifications',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (widget.notifications.isNotEmpty)
                TextButton(
                  onPressed: widget.onDismissAll,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'No notifications',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            for (var index = 0; index < sorted.length; index++) ...[
              Dismissible(
                key: ValueKey<String>('notification-panel-${sorted[index].id}'),
                direction: DismissDirection.startToEnd,
                dismissThresholds: const {DismissDirection.startToEnd: 0.35},
                onDismissed: (_) => _dismissNotification(sorted[index].id),
                child: NotificationCard(
                  notification: sorted[index],
                  onDismiss: () => _dismissNotification(sorted[index].id),
                  onInvokeAction: (key) {
                    debugPrint(
                      '[notification-panel] action id=${sorted[index].id} key=$key',
                    );
                    widget.onInvokeAction(sorted[index].id, key);
                  },
                ),
              ),
              if (index != sorted.length - 1) const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}
