import 'package:flutter/material.dart';

import '../models/alice_config.dart';
import '../models/bar_snapshot.dart';
import '../state/panel_controller.dart';

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.config,
    required this.snapshot,
    required this.panelController,
    required this.onBackgroundTap,
  });

  final AliceConfig config;
  final BarSnapshot snapshot;
  final PanelController panelController;
  final VoidCallback onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVisible = config.maxVisibleTrayItems > 0
        ? config.maxVisibleTrayItems - 1
        : 0;
    final visibleTrayItems = snapshot.trayItems.take(maxVisible).toList();
    final overflowCount = snapshot.trayItems.length - visibleTrayItems.length;

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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: snapshot.workspaces
                      .map((workspace) => _WorkspaceChip(workspace: workspace))
                      .toList(),
                ),
              ),
              Expanded(
                child: Center(
                  child: snapshot.media == null
                      ? const SizedBox.shrink()
                      : _PanelTapTarget(
                          alignment: PanelAlignment.center,
                          onTap: (anchor) =>
                              panelController.toggle(AlicePanel.media, anchor),
                          child: _Pill(
                            icon: snapshot.media!.isPlaying
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            label:
                                '${snapshot.media!.title} - ${snapshot.media!.artist} - ${snapshot.media!.positionLabel}/${snapshot.media!.lengthLabel}',
                            highlighted: panelController.isOpen(
                              AlicePanel.media,
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
                    _MetricPill(
                      icon: Icons.memory_rounded,
                      label:
                          '${snapshot.memoryUsagePercent.toStringAsFixed(0)}%',
                      alert: snapshot.memoryUsagePercent >= 90,
                      warning: snapshot.memoryUsagePercent >= 75,
                    ),
                    _MetricPill(
                      icon: Icons.developer_board_rounded,
                      label: snapshot.cpuUsageCores.toStringAsFixed(1),
                      alert: snapshot.cpuUsageCores >= 3.2,
                      warning: snapshot.cpuUsageCores >= 2.4,
                    ),
                    _Pill(
                      icon: switch (snapshot.network.kind) {
                        NetworkKind.wifi => Icons.wifi_rounded,
                        NetworkKind.wired => Icons.settings_ethernet_rounded,
                        NetworkKind.disconnected =>
                          Icons.portable_wifi_off_rounded,
                      },
                      label: config.showNetworkLabel
                          ? snapshot.network.label
                          : '',
                    ),
                    _PanelTapTarget(
                      alignment: PanelAlignment.right,
                      onTap: (anchor) =>
                          panelController.toggle(AlicePanel.clock, anchor),
                      child: _Pill(
                        icon: Icons.schedule_rounded,
                        label:
                            '${snapshot.clock.timeZoneCode} ${snapshot.clock.dateLabel} ${snapshot.clock.timeLabel}',
                        highlighted: panelController.isOpen(AlicePanel.clock),
                      ),
                    ),
                    ...visibleTrayItems.map(
                      (item) =>
                          _Pill(icon: Icons.apps_rounded, label: item.label),
                    ),
                    if (overflowCount > 0)
                      _PanelTapTarget(
                        alignment: PanelAlignment.right,
                        onTap: (anchor) => panelController.toggle(
                          AlicePanel.trayOverflow,
                          anchor,
                        ),
                        child: _Pill(
                          icon: Icons.expand_more_rounded,
                          label: '$overflowCount more',
                          highlighted: panelController.isOpen(
                            AlicePanel.trayOverflow,
                          ),
                        ),
                      ),
                    _PanelTapTarget(
                      alignment: PanelAlignment.right,
                      onTap: (anchor) =>
                          panelController.toggle(AlicePanel.power, anchor),
                      child: _Pill(
                        icon: Icons.power_settings_new_rounded,
                        label: '',
                        highlighted: panelController.isOpen(AlicePanel.power),
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

class _PanelTapTarget extends StatefulWidget {
  const _PanelTapTarget({
    required this.alignment,
    required this.onTap,
    required this.child,
  });

  final PanelAlignment alignment;
  final ValueChanged<PanelAnchor> onTap;
  final Widget child;

  @override
  State<_PanelTapTarget> createState() => _PanelTapTargetState();
}

class _PanelTapTargetState extends State<_PanelTapTarget> {
  Offset? _lastTapPosition;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        _lastTapPosition = details.globalPosition;
      },
      onTap: () {
        final anchor = PanelAnchor(
          globalPosition: _lastTapPosition ?? Offset.zero,
          alignment: widget.alignment,
        );
        widget.onTap(anchor);
      },
      onTapUp: (_) {},
      child: widget.child,
    );
  }
}

class _WorkspaceChip extends StatelessWidget {
  const _WorkspaceChip({required this.workspace});

  final WorkspaceSnapshot workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = workspace.isFocused
        ? theme.colorScheme.primary
        : workspace.isVisible
        ? theme.colorScheme.secondary
        : Colors.transparent;
    final foreground = workspace.isFocused
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        workspace.label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: workspace.isFocused ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : theme.colorScheme.secondary.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
        border: highlighted
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.alert,
    required this.warning,
  });

  final IconData icon;
  final String label;
  final bool alert;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = alert
        ? const Color(0xFFD1495B)
        : warning
        ? const Color(0xFFE9B44C)
        : theme.colorScheme.secondary.withValues(alpha: 0.75);
    final foreground = alert || warning
        ? Colors.black
        : theme.colorScheme.onSurface;

    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
