import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../alice_config.dart';
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
import 'bar_widgets/tray_module.dart';
import 'bar_widgets/workspace_module.dart';

class TopBar extends StatefulWidget {
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

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  Widget _probe(String name, Widget child) {
    widget.onModuleBuild?.call(name);
    return child;
  }

  @override
  void didUpdateWidget(TopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.snapshotState.updateConfig(widget.config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onBackgroundTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: widget.config.transparentTopBar
              ? null
              : theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(0),
          border: widget.config.transparentTopBar
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
                  valueListenable: widget.snapshotState.workspaces,
                  builder: (context, workspaces, _) => _probe(
                    'workspace',
                    TopBarWorkspaceModule(
                      workspaces: workspaces,
                      onWorkspaceTap: widget.onWorkspaceTap,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ValueListenableBuilder<MediaSnapshot?>(
                    valueListenable: widget.snapshotState.media,
                    builder: (context, media, _) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.panelController.mediaOpen,
                          builder: (context, highlighted, _) => _probe(
                            'media',
                            TopBarMediaModule(
                              media: media,
                              highlighted: highlighted,
                              onToggle: (anchor) => widget.panelController
                                  .toggle(AlicePanel.media, anchor),
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
                      valueListenable: widget.snapshotState.memoryUsagePercent,
                      builder: (context, value, _) => _probe(
                        'memory',
                        TopBarMemoryModule(memoryUsagePercent: value),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: widget.snapshotState.cpuUsageCores,
                      builder: (context, value, _) =>
                          _probe('cpu', TopBarCpuModule(cpuUsageCores: value)),
                    ),
                    ValueListenableBuilder<NetworkSnapshot>(
                      valueListenable: widget.snapshotState.network,
                      builder: (context, network, _) => _probe(
                        'network',
                        TopBarNetworkModule(
                          networkKind: network.kind,
                          label: widget.config.showNetworkLabel
                              ? network.label
                              : '',
                        ),
                      ),
                    ),
                    ValueListenableBuilder<ClockSnapshot>(
                      valueListenable: widget.snapshotState.clock,
                      builder: (context, clock, _) =>
                          ValueListenableBuilder<bool>(
                            valueListenable: widget.panelController.clockOpen,
                            builder: (context, highlighted, _) => _probe(
                              'clock',
                              TopBarClockModule(
                                localTimeZoneLabel:
                                    widget.config.localTimeZoneLabel ??
                                    clock.timeZoneCode,
                                clock: clock,
                                highlighted: highlighted,
                                onToggle: (anchor) => widget.panelController
                                    .toggle(AlicePanel.clock, anchor),
                              ),
                            ),
                          ),
                    ),
                    _TrayCluster(
                      visibleTrayItems: widget.snapshotState.visibleTrayItems,
                      trayOverflowCount: widget.snapshotState.trayOverflowCount,
                      trayOverflowOpen: widget.panelController.trayOverflowOpen,
                      onTrayItemTap: widget.onTrayItemTap,
                      onTrayOverflowToggle: (anchor) => widget.panelController
                          .toggle(AlicePanel.trayOverflow, anchor),
                      probe: _probe,
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable:
                          widget.snapshotState.unreadNotificationCount,
                      builder: (context, unreadCount, _) =>
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                widget.panelController.notificationsOpen,
                            builder: (context, highlighted, _) => _probe(
                              'notifications',
                              TopBarNotificationModule(
                                unreadCount: unreadCount,
                                highlighted: highlighted,
                                onToggle: (anchor) => widget.panelController
                                    .toggle(AlicePanel.notifications, anchor),
                              ),
                            ),
                          ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.panelController.powerOpen,
                      builder: (context, highlighted, _) => _probe(
                        'power',
                        TopBarPowerModule(
                          highlighted: highlighted,
                          onToggle: (anchor) => widget.panelController.toggle(
                            AlicePanel.power,
                            anchor,
                          ),
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
