import 'package:flutter/material.dart';

import '../data/alice_config.dart';
import '../data/bar_snapshot.dart';
import '../state/panel_controller.dart';
import 'top_bar/widgets/clock_module.dart';
import 'top_bar/widgets/cpu_module.dart';
import 'top_bar/widgets/media_module.dart';
import 'top_bar/widgets/memory_module.dart';
import 'top_bar/widgets/network_module.dart';
import 'top_bar/widgets/power_module.dart';
import 'top_bar/widgets/tray_module.dart';
import 'top_bar/widgets/workspace_module.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.config,
    required this.snapshot,
    required this.panelController,
    required this.onWorkspaceTap,
    required this.onTrayItemTap,
    required this.onBackgroundTap,
  });

  final AliceConfig config;
  final BarSnapshot snapshot;
  final PanelController panelController;
  final ValueChanged<String> onWorkspaceTap;
  final ValueChanged<TrayItemSnapshot> onTrayItemTap;
  final VoidCallback onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVisible = config.maxVisibleTrayItems > 0
        ? config.maxVisibleTrayItems - 1
        : 0;
    final visibleTrayItems = snapshot.trayItems.take(maxVisible).toList();
    final overflowCount = snapshot.trayItems.length - visibleTrayItems.length;
    final localTimeZoneLabel =
        config.localTimeZoneLabel ?? snapshot.clock.timeZoneCode;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBackgroundTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(0),
          border: Border.all(
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
                child: TopBarWorkspaceModule(
                  workspaces: snapshot.workspaces,
                  onWorkspaceTap: onWorkspaceTap,
                ),
              ),
              Expanded(
                child: Center(
                  child: TopBarMediaModule(
                    media: snapshot.media,
                    highlighted: panelController.isOpen(AlicePanel.media),
                    onToggle: (anchor) =>
                        panelController.toggle(AlicePanel.media, anchor),
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
                    TopBarMemoryModule(
                      memoryUsagePercent: snapshot.memoryUsagePercent,
                    ),
                    TopBarCpuModule(cpuUsageCores: snapshot.cpuUsageCores),
                    TopBarNetworkModule(
                      networkKind: snapshot.network.kind,
                      label: config.showNetworkLabel
                          ? snapshot.network.label
                          : '',
                    ),
                    TopBarClockModule(
                      localTimeZoneLabel: localTimeZoneLabel,
                      clock: snapshot.clock,
                      highlighted: panelController.isOpen(AlicePanel.clock),
                      onToggle: (anchor) =>
                          panelController.toggle(AlicePanel.clock, anchor),
                    ),
                    if (visibleTrayItems.isNotEmpty)
                      TopBarTrayGroupModule(
                        items: visibleTrayItems,
                        onItemTap: onTrayItemTap,
                      ),
                    if (overflowCount > 0)
                      TopBarTrayOverflowModule(
                        overflowCount: overflowCount,
                        highlighted: panelController.isOpen(
                          AlicePanel.trayOverflow,
                        ),
                        onToggle: (anchor) => panelController.toggle(
                          AlicePanel.trayOverflow,
                          anchor,
                        ),
                      ),
                    TopBarPowerModule(
                      highlighted: panelController.isOpen(AlicePanel.power),
                      onToggle: (anchor) =>
                          panelController.toggle(AlicePanel.power, anchor),
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
