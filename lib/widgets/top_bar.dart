import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../alice_config.dart';
import '../rust_gen/caldav/models.dart';
import '../rust_gen/state.dart';
import '../panel_controller.dart';
import '../snapshot_state.dart';
import 'bar_widgets/clock_module.dart';
import 'bar_widgets/cpu_module.dart';
import 'bar_widgets/media_module.dart';
import 'bar_widgets/memory_module.dart';
import 'bar_widgets/network_module.dart';
import 'bar_widgets/notification_module.dart';
import 'bar_widgets/power_module.dart';
import 'bar_widgets/task_module.dart';
import 'bar_widgets/tray_module.dart';
import 'bar_widgets/weather_module.dart';
import 'bar_widgets/workspace_module.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.config,
    required this.snapshotState,
    required this.panelController,
    required this.onWorkspaceTap,
    required this.onTrayItemTap,
    required this.onBackgroundTap,
    this.onModuleBuild,
  });

  final AliceConfig config;
  final AliceSnapshotState snapshotState;
  final PanelController panelController;
  final ValueChanged<String> onWorkspaceTap;
  final ValueChanged<TrayItemSnapshot> onTrayItemTap;
  final VoidCallback onBackgroundTap;
  final ValueChanged<String>? onModuleBuild;

  Widget _probe(String name, Widget child) {
    onModuleBuild?.call(name);
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBackgroundTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: config.transparentTopBar
              ? null
              : theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(0),
          border: config.transparentTopBar
              ? null
              : Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                ),
        ),
        child: DefaultTextStyle(
          style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            overflow: TextOverflow.ellipsis,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ValueListenableBuilder<List<WorkspaceSnapshot>>(
                  valueListenable: snapshotState.workspaces,
                  builder: (context, workspaces, _) => _probe(
                    'workspace',
                    TopBarWorkspaceModule(
                      workspaces: workspaces,
                      onWorkspaceTap: onWorkspaceTap,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ValueListenableBuilder<MediaSnapshot?>(
                    valueListenable: snapshotState.media,
                    builder: (context, media, _) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: panelController.mediaOpen,
                          builder: (context, highlighted, _) => _probe(
                            'media',
                            TopBarMediaModule(
                              media: media,
                              highlighted: highlighted,
                              onToggle: (anchor) => panelController.toggle(
                                AlicePanel.media,
                                anchor,
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: snapshotState.memoryUsagePercent,
                      builder: (context, value, _) => _probe(
                        'memory',
                        TopBarMemoryModule(memoryUsagePercent: value),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: snapshotState.cpuUsageCores,
                      builder: (context, value, _) =>
                          _probe('cpu', TopBarCpuModule(cpuUsageCores: value)),
                    ),
                    ValueListenableBuilder<NetworkSnapshot>(
                      valueListenable: snapshotState.network,
                      builder: (context, network, _) => _probe(
                        'network',
                        TopBarNetworkModule(
                          networkKind: network.kind,
                          label: config.showNetworkLabel ? network.label : '',
                        ),
                      ),
                    ),
                    if (config.caldav != null)
                      _TaskModuleBindings(
                        snapshotState: snapshotState,
                        panelController: panelController,
                        probe: _probe,
                      ),
                    ValueListenableBuilder<ClockSnapshot>(
                      valueListenable: snapshotState.clock,
                      builder: (context, clock, _) =>
                          ValueListenableBuilder<bool>(
                            valueListenable: panelController.clockOpen,
                            builder: (context, highlighted, _) => _probe(
                              'clock',
                              TopBarClockModule(
                                localTimeZoneLabel:
                                    config.localTimeZoneLabel ??
                                    clock.timeZoneCode,
                                clock: clock,
                                highlighted: highlighted,
                                onToggle: (anchor) => panelController.toggle(
                                  AlicePanel.clock,
                                  anchor,
                                ),
                              ),
                            ),
                          ),
                    ),
                    if (config.weather.enable)
                      ValueListenableBuilder<WeatherSnapshot?>(
                        valueListenable: snapshotState.weather,
                        builder: (context, weather, _) =>
                            ValueListenableBuilder<bool>(
                              valueListenable: panelController.weatherOpen,
                              builder: (context, highlighted, _) => _probe(
                                'weather',
                                TopBarWeatherModule(
                                  weather: weather,
                                  highlighted: highlighted,
                                  onToggle: (anchor) => panelController.toggle(
                                    AlicePanel.weather,
                                    anchor,
                                  ),
                                ),
                              ),
                            ),
                      ),
                    _TrayCluster(
                      visibleTrayItems: snapshotState.visibleTrayItems,
                      trayOverflowCount: snapshotState.trayOverflowCount,
                      trayOverflowOpen: panelController.trayOverflowOpen,
                      onTrayItemTap: onTrayItemTap,
                      onTrayOverflowToggle: (anchor) => panelController.toggle(
                        AlicePanel.trayOverflow,
                        anchor,
                      ),
                      probe: _probe,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: snapshotState.unreadNotificationCount,
                      builder: (context, unreadCount, _) =>
                          ValueListenableBuilder<bool>(
                            valueListenable: panelController.notificationsOpen,
                            builder: (context, highlighted, _) => _probe(
                              'notifications',
                              TopBarNotificationModule(
                                unreadCount: unreadCount,
                                highlighted: highlighted,
                                onToggle: (anchor) => panelController.toggle(
                                  AlicePanel.notifications,
                                  anchor,
                                ),
                              ),
                            ),
                          ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: panelController.powerOpen,
                      builder: (context, highlighted, _) => _probe(
                        'power',
                        TopBarPowerModule(
                          highlighted: highlighted,
                          onToggle: (anchor) =>
                              panelController.toggle(AlicePanel.power, anchor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskModuleBindings extends StatelessWidget {
  const _TaskModuleBindings({
    required this.snapshotState,
    required this.panelController,
    required this.probe,
  });

  final AliceSnapshotState snapshotState;
  final PanelController panelController;
  final Widget Function(String name, Widget child) probe;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: snapshotState.dueTodayTaskCount,
    builder: (context, dueToday, _) => ValueListenableBuilder<int>(
      valueListenable: snapshotState.overdueTaskCount,
      builder: (context, overdue, _) => ValueListenableBuilder<CalDavSyncState>(
        valueListenable: snapshotState.caldavSyncState,
        builder: (context, syncState, _) => ValueListenableBuilder<bool>(
          valueListenable: panelController.tasksOpen,
          builder: (context, highlighted, _) => probe(
            'tasks',
            TopBarTaskModule(
              dueTodayCount: dueToday,
              overdueCount: overdue,
              syncState: syncState,
              highlighted: highlighted,
              onToggle: (anchor) =>
                  panelController.toggle(AlicePanel.tasks, anchor),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TrayCluster extends StatelessWidget {
  const _TrayCluster({
    required this.visibleTrayItems,
    required this.trayOverflowCount,
    required this.trayOverflowOpen,
    required this.onTrayItemTap,
    required this.onTrayOverflowToggle,
    required this.probe,
  });

  final ValueListenable<List<TrayItemSnapshot>> visibleTrayItems;
  final ValueListenable<int> trayOverflowCount;
  final ValueListenable<bool> trayOverflowOpen;
  final ValueChanged<TrayItemSnapshot> onTrayItemTap;
  final ValueChanged<PanelAnchor> onTrayOverflowToggle;
  final Widget Function(String name, Widget child) probe;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TrayItemSnapshot>>(
      valueListenable: visibleTrayItems,
      builder: (context, items, _) => ValueListenableBuilder<int>(
        valueListenable: trayOverflowCount,
        builder: (context, overflowCount, _) {
          if (items.isEmpty && overflowCount <= 0) {
            return const SizedBox.shrink();
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.isNotEmpty)
                probe(
                  'tray',
                  TopBarTrayGroupModule(items: items, onItemTap: onTrayItemTap),
                ),
              if (items.isNotEmpty && overflowCount > 0)
                const SizedBox(width: 8),
              if (overflowCount > 0)
                ValueListenableBuilder<bool>(
                  valueListenable: trayOverflowOpen,
                  builder: (context, highlighted, _) => probe(
                    'trayOverflow',
                    TopBarTrayOverflowModule(
                      overflowCount: overflowCount,
                      highlighted: highlighted,
                      onToggle: onTrayOverflowToggle,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
