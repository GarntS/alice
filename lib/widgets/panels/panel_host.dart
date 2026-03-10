import 'package:flutter/material.dart';

import '../../models/alice_config.dart';
import '../../models/bar_snapshot.dart';
import '../../state/panel_controller.dart';
import 'panel_spec.dart';

AlicePanel? alicePanelFromId(String? panelId) {
  return switch (panelId) {
    'media' => AlicePanel.media,
    'clock' => AlicePanel.clock,
    'trayOverflow' => AlicePanel.trayOverflow,
    'power' => AlicePanel.power,
    _ => null,
  };
}

class AlicePanelCard extends StatelessWidget {
  const AlicePanelCard({
    super.key,
    required this.panel,
    required this.config,
    required this.snapshot,
    required this.onPowerAction,
    required this.onMediaAction,
  });

  final AlicePanel panel;
  final AliceConfig config;
  final BarSnapshot snapshot;
  final Future<void> Function(String) onPowerAction;
  final Future<void> Function(String) onMediaAction;

  @override
  Widget build(BuildContext context) {
    final panelSize = alicePanelSize(panel, config: config, snapshot: snapshot);
    final content = switch (panel) {
      AlicePanel.media => _MediaPanel(
        media: snapshot.media,
        onAction: onMediaAction,
      ),
      AlicePanel.clock => _ClockPanel(config: config, snapshot: snapshot.clock),
      AlicePanel.trayOverflow => _TrayPanel(
        trayItems: snapshot.trayItems,
        maxVisibleTrayItems: config.maxVisibleTrayItems,
      ),
      AlicePanel.power => _PowerPanel(onAction: onPowerAction),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelSize.width,
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

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _MediaPanel extends StatelessWidget {
  const _MediaPanel({required this.media, required this.onAction});

  final MediaSnapshot? media;
  final Future<void> Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (media == null) {
      return const _PanelShell(
        title: 'Media',
        child: Text('No active MPRIS player.'),
      );
    }

    return _PanelShell(
      title: 'Media',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            media!.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(media!.artist, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('${media!.positionLabel} / ${media!.lengthLabel}'),
          const SizedBox(height: 16),
          Row(
            children: [
              _ActionButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () => onAction('previous'),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: media!.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: () => onAction('playPause'),
                filled: true,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.skip_next_rounded,
                onPressed: () => onAction('next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClockPanel extends StatelessWidget {
  const _ClockPanel({required this.config, required this.snapshot});

  final AliceConfig config;
  final ClockSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final nowUtc = DateTime.now().toUtc();
    return _PanelShell(
      title: 'World Clock',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClockRow(
            label: snapshot.timeZoneCode,
            dateLabel: snapshot.dateLabel,
            timeLabel: snapshot.timeLabel,
            highlighted: true,
          ),
          const SizedBox(height: 8),
          ...config.timeZones.map((zone) {
            final zoned = nowUtc.add(Duration(hours: zone.offsetHours));
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ClockRow(
                label: zone.label,
                dateLabel:
                    '${zoned.day.toString().padLeft(2, '0')} ${_monthName(zoned.month)}',
                timeLabel:
                    '${zoned.hour.toString().padLeft(2, '0')}:${zoned.minute.toString().padLeft(2, '0')}',
              ),
            );
          }),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _TrayPanel extends StatelessWidget {
  const _TrayPanel({
    required this.trayItems,
    required this.maxVisibleTrayItems,
  });

  final List<TrayItemSnapshot> trayItems;
  final int maxVisibleTrayItems;

  @override
  Widget build(BuildContext context) {
    final overflow = trayItems.skip(
      maxVisibleTrayItems > 0 ? maxVisibleTrayItems - 1 : 0,
    );
    final items = overflow.toList();
    return _PanelShell(
      title: 'Tray Overflow',
      child: items.isEmpty
          ? const Text('No overflow tray items.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: items
                  .map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.apps_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.label)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _PowerPanel extends StatelessWidget {
  const _PowerPanel({required this.onAction});

  final Future<void> Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Power',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PowerButton(
            label: 'Lock',
            icon: Icons.lock_outline_rounded,
            onPressed: () => onAction('lock'),
          ),
          const SizedBox(height: 6),
          _PowerButton(
            label: 'Lock + Suspend',
            icon: Icons.bedtime_rounded,
            onPressed: () => onAction('lockAndSuspend'),
          ),
          const SizedBox(height: 6),
          _PowerButton(
            label: 'Restart',
            icon: Icons.restart_alt_rounded,
            onPressed: () => onAction('restart'),
          ),
          const SizedBox(height: 6),
          _PowerButton(
            label: 'Power Off',
            icon: Icons.power_settings_new_rounded,
            onPressed: () => onAction('poweroff'),
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.label,
    required this.dateLabel,
    required this.timeLabel,
    this.highlighted = false,
  });

  final String label;
  final String dateLabel;
  final String timeLabel;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(dateLabel),
          const SizedBox(width: 12),
          Text(timeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 48,
        height: 44,
        decoration: BoxDecoration(
          color: filled
              ? theme.colorScheme.primary.withValues(alpha: 0.18)
              : theme.colorScheme.secondary.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = destructive
        ? const Color(0xFFD1495B).withValues(alpha: 0.15)
        : theme.colorScheme.secondary.withValues(alpha: 0.55);
    final foreground = destructive
        ? const Color(0xFFD1495B)
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
