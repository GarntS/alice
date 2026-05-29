import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import 'panel_spec.dart';
import 'media_panel.dart';
import 'clock_panel.dart';
import 'tray_panel.dart';
import 'power_panel.dart';
import 'notification_panel.dart';

class AlicePanelCard extends StatelessWidget {
  const AlicePanelCard({
    super.key,
    required this.panel,
    required this.config,
    required this.snapshot,
    required this.onPowerAction,
    required this.onMediaAction,
    required this.onSeekMedia,
    required this.onTrayAction,
    required this.onDismissNotification,
    required this.onDismissAllNotifications,
    required this.onMarkAllNotificationsRead,
    required this.onInvokeNotificationAction,
    this.screenHeight = 1080.0,
  });

  final AlicePanel panel;
  final AliceConfig config;
  final BarSnapshot snapshot;
  final Future<void> Function(String) onPowerAction;
  final Future<void> Function(String) onMediaAction;
  final Future<void> Function(int) onSeekMedia;
  final Future<void> Function(TrayItemSnapshot) onTrayAction;
  final Future<void> Function(int id) onDismissNotification;
  final Future<void> Function() onDismissAllNotifications;
  final Future<void> Function() onMarkAllNotificationsRead;
  final Future<void> Function(int id, String actionKey)
  onInvokeNotificationAction;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    final panelSize = alicePanelSize(
      panel,
      config: config,
      snapshot: snapshot,
      screenHeight: screenHeight,
    );
    final content = switch (panel) {
      AlicePanel.media => MediaPanel(
        media: snapshot.media,
        onAction: onMediaAction,
        onSeek: onSeekMedia,
      ),
      AlicePanel.clock => ClockPanel(config: config, snapshot: snapshot.clock),
      AlicePanel.trayOverflow => TrayPanel(
        trayItems: snapshot.trayItems,
        maxVisibleTrayItems: config.maxVisibleTrayItems,
        onTrayAction: onTrayAction,
      ),
      AlicePanel.power => PowerPanel(onAction: onPowerAction),
      AlicePanel.notifications => NotificationPanel(
        notifications: snapshot.notifications,
        onDismissAll: onDismissAllNotifications,
        onDismissOne: (id) => onDismissNotification(id),
        onMarkAllRead: onMarkAllNotificationsRead,
        onInvokeAction: (id, key) => onInvokeNotificationAction(id, key),
      ),
    };

    final hasDynamicHeight =
        panel == AlicePanel.clock ||
        panel == AlicePanel.media ||
        panel == AlicePanel.notifications;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelSize.width,
        height: hasDynamicHeight ? null : panelSize.height,
        constraints: hasDynamicHeight
            ? BoxConstraints(maxHeight: panelSize.height)
            : null,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}
