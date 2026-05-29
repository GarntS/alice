import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import '../../snapshot_state.dart';
import 'panel_spec.dart';
import 'media_panel.dart';
import 'clock_panel.dart';
import 'tray_panel.dart';
import 'power_panel.dart';
import 'notification_panel.dart';

class AlicePanelCard extends StatefulWidget {
  const AlicePanelCard({
    super.key,
    required this.panel,
    required this.config,
    required this.snapshotState,
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
  final AliceSnapshotState snapshotState;
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
  State<AlicePanelCard> createState() => _AlicePanelCardState();
}

class _AlicePanelCardState extends State<AlicePanelCard> {
  @override
  void didUpdateWidget(AlicePanelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.snapshotState.updateConfig(widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaSnapshot?>(
      valueListenable: widget.snapshotState.media,
      builder: (context, media, _) => ValueListenableBuilder<int>(
        valueListenable: widget.snapshotState.trayOverflowCount,
        builder: (context, overflowCount, _) {
          final panelSize = alicePanelSizeFromSlices(
            widget.panel,
            config: widget.config,
            media: media,
            trayOverflowCount: overflowCount,
            screenHeight: widget.screenHeight,
          );
          final content = switch (widget.panel) {
            AlicePanel.media => ValueListenableBuilder<MediaSnapshot?>(
              valueListenable: widget.snapshotState.media,
              builder: (context, media, _) => MediaPanel(
                media: media,
                onAction: widget.onMediaAction,
                onSeek: widget.onSeekMedia,
              ),
            ),
            AlicePanel.clock => ValueListenableBuilder<ClockSnapshot>(
              valueListenable: widget.snapshotState.clock,
              builder: (context, clock, _) =>
                  ClockPanel(config: widget.config, snapshot: clock),
            ),
            AlicePanel.trayOverflow =>
              ValueListenableBuilder<List<TrayItemSnapshot>>(
                valueListenable: widget.snapshotState.trayItems,
                builder: (context, trayItems, _) => TrayPanel(
                  trayItems: trayItems,
                  maxVisibleTrayItems: widget.config.maxVisibleTrayItems,
                  onTrayAction: widget.onTrayAction,
                ),
              ),
            AlicePanel.power => PowerPanel(onAction: widget.onPowerAction),
            AlicePanel.notifications =>
              ValueListenableBuilder<List<NotificationSnapshot>>(
                valueListenable: widget.snapshotState.notifications,
                builder: (context, notifications, _) => NotificationPanel(
                  notifications: notifications,
                  onDismissAll: widget.onDismissAllNotifications,
                  onDismissOne: (id) => widget.onDismissNotification(id),
                  onMarkAllRead: widget.onMarkAllNotificationsRead,
                  onInvokeAction: (id, key) =>
                      widget.onInvokeNotificationAction(id, key),
                ),
              ),
          };

          final hasDynamicHeight =
              widget.panel == AlicePanel.clock ||
              widget.panel == AlicePanel.media ||
              widget.panel == AlicePanel.notifications;
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
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.96),
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
        },
      ),
    );
  }
}
