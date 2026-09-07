import 'package:material_ui/material_ui.dart';

import '../../alice_config.dart';
import '../../alice_theme.dart';
import '../../rust_gen/caldav/models.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import '../../snapshot_state.dart';
import 'panel_sizes.dart';
import 'media_panel.dart';
import 'network_panel.dart';
import 'clock_panel.dart';
import 'tray_panel.dart';
import 'task_panel.dart';
import 'power_panel.dart';
import 'notification_panel.dart';
import 'weather_panel.dart';

class AlicePanelCard extends StatelessWidget {
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
    this.onTaskRefresh,
    this.onTaskCompletion,
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
  final Future<void> Function()? onTaskRefresh;
  final Future<void> Function(TaskResourceIdentity identity, bool completed)?
  onTaskCompletion;

  @override
  Widget build(BuildContext context) {
    final panelSize = alicePanelSize(panel);
    final content = switch (panel) {
      AlicePanel.media => ValueListenableBuilder<MediaSnapshot?>(
        valueListenable: snapshotState.media,
        builder: (context, media, _) => MediaPanel(
          media: media,
          onAction: onMediaAction,
          onSeek: onSeekMedia,
        ),
      ),
      AlicePanel.network => ValueListenableBuilder<NetworkSnapshot>(
        valueListenable: snapshotState.network,
        builder: (context, network, _) => NetworkPanel(network: network),
      ),
      AlicePanel.clock => ValueListenableBuilder<ClockSnapshot>(
        valueListenable: snapshotState.clock,
        builder: (context, clock, _) =>
            ClockPanel(config: config, snapshot: clock),
      ),
      AlicePanel.tasks => ValueListenableBuilder<List<NormalizedTask>>(
        valueListenable: snapshotState.tasks,
        builder: (context, tasks, _) => ValueListenableBuilder<CalDavSyncState>(
          valueListenable: snapshotState.caldavSyncState,
          builder: (context, syncState, _) => TaskPanel(
            tasks: tasks,
            syncState: syncState,
            onRefresh: onTaskRefresh ?? () async {},
            onCompletion: onTaskCompletion ?? (_, __) async {},
          ),
        ),
      ),
      AlicePanel.weather => ValueListenableBuilder<WeatherSnapshot?>(
        valueListenable: snapshotState.weather,
        builder: (context, weather, _) =>
            WeatherPanel(config: config, weather: weather),
      ),
      AlicePanel.trayOverflow => ValueListenableBuilder<List<TrayItemSnapshot>>(
        valueListenable: snapshotState.trayItems,
        builder: (context, trayItems, _) => TrayPanel(
          trayItems: trayItems,
          maxVisibleTrayItems: config.maxVisibleTrayItems,
          onTrayAction: onTrayAction,
        ),
      ),
      AlicePanel.power => PowerPanel(onAction: onPowerAction),
      AlicePanel.notifications =>
        ValueListenableBuilder<List<NotificationSnapshot>>(
          valueListenable: snapshotState.notifications,
          builder: (context, notifications, _) => NotificationPanel(
            notifications: notifications,
            onDismissAll: onDismissAllNotifications,
            onDismissOne: (id) => onDismissNotification(id),
            onMarkAllRead: onMarkAllNotificationsRead,
            onInvokeAction: (id, key) => onInvokeNotificationAction(id, key),
          ),
        ),
    };

    final colors = AliceColorTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelSize.width,
        constraints: BoxConstraints(maxHeight: panelSize.height),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.accentBorder),
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
