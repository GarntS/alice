import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import 'panel_spec.dart';

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
  });

  final AlicePanel panel;
  final AliceConfig config;
  final BarSnapshot snapshot;
  final Future<void> Function(String) onPowerAction;
  final Future<void> Function(String) onMediaAction;
  final Future<void> Function(int) onSeekMedia;
  final Future<void> Function(TrayItemSnapshot) onTrayAction;

  @override
  Widget build(BuildContext context) {
    final panelSize = alicePanelSize(panel, config: config, snapshot: snapshot);
    final content = switch (panel) {
      AlicePanel.media => _MediaPanel(
        media: snapshot.media,
        onAction: onMediaAction,
        onSeek: onSeekMedia,
      ),
      AlicePanel.clock => _ClockPanel(config: config, snapshot: snapshot.clock),
      AlicePanel.trayOverflow => _TrayPanel(
        trayItems: snapshot.trayItems,
        maxVisibleTrayItems: config.maxVisibleTrayItems,
        onTrayAction: onTrayAction,
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
  const _PanelShell({
    required this.title,
    required this.child,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.titleAlign = TextAlign.start,
  });

  final String? title;
  final Widget child;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign titleAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = title?.trim() ?? '';
    final hasTitle = titleText.isNotEmpty;

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle) ...[
          Text(
            titleText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: titleAlign,
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }
}

class _MediaPanel extends StatefulWidget {
  const _MediaPanel({
    required this.media,
    required this.onAction,
    required this.onSeek,
  });

  final MediaSnapshot? media;
  final Future<void> Function(String) onAction;
  final Future<void> Function(int) onSeek;

  @override
  State<_MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<_MediaPanel> {
  double? _dragValue;

  String _formatMicros(int micros) {
    final totalSeconds = micros.clamp(0, 999999999) ~/ 1000000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = widget.media;
    if (media == null) {
      return const _PanelShell(
        title: null,
        crossAxisAlignment: CrossAxisAlignment.center,
        titleAlign: TextAlign.center,
        child: Text('No active MPRIS player.'),
      );
    }

    final albumTitle = media.albumTitle.trim();
    final hasAlbumArt = media.artUrl.trim().isNotEmpty;
    final header = hasAlbumArt
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _AlbumArt(url: media.artUrl),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ScrollingText(
                      text: media.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ScrollingText(
                      text: media.artist,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (albumTitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ScrollingText(
                        text: albumTitle,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScrollingText(
                text: media.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              _ScrollingText(
                text: media.artist,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (albumTitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ScrollingText(
                  text: albumTitle,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          );

    final canSeek = media.lengthMicros > 0;
    final sliderValue = canSeek
        ? (_dragValue ?? (media.positionMicros / media.lengthMicros))
              .clamp(0.0, 1.0)
        : 0.0;
    final positionLabel = _dragValue != null && canSeek
        ? _formatMicros((_dragValue! * media.lengthMicros).round())
        : media.positionLabel;

    return _PanelShell(
      title: null,
      crossAxisAlignment: CrossAxisAlignment.center,
      titleAlign: TextAlign.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: 12),
          Row(
            children: [
              Text(positionLabel, style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(media.lengthLabel, style: theme.textTheme.bodySmall),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
            ),
            child: Slider(
              value: sliderValue,
              onChanged: canSeek
                  ? (v) => setState(() => _dragValue = v)
                  : null,
              onChangeEnd: canSeek
                  ? (v) {
                      widget.onSeek((v * media.lengthMicros).round());
                      setState(() => _dragValue = null);
                    }
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () => widget.onAction('previous'),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: media.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: () => widget.onAction('playPause'),
                filled: true,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.skip_next_rounded,
                onPressed: () => widget.onAction('next'),
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
    final localTimeZoneLabel =
        config.localTimeZoneLabel ?? snapshot.timeZoneCode;
    return _PanelShell(
      title: 'World Clock',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClockRow(
            label: localTimeZoneLabel,
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
    required this.onTrayAction,
  });

  final List<TrayItemSnapshot> trayItems;
  final int maxVisibleTrayItems;
  final Future<void> Function(TrayItemSnapshot) onTrayAction;

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
                    (item) => InkWell(
                      onTap: () => onTrayAction(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
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
                            _TrayItemIcon(iconPngBytes: item.iconPngBytes),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item.label)),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _TrayItemIcon extends StatelessWidget {
  const _TrayItemIcon({required this.iconPngBytes});

  final Uint8List? iconPngBytes;

  @override
  Widget build(BuildContext context) {
    if (iconPngBytes == null || iconPngBytes!.isEmpty) {
      return const Icon(Icons.apps_rounded, size: 18);
    }

    return Image.memory(
      iconPngBytes!,
      width: 18,
      height: 18,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.apps_rounded, size: 18);
      },
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

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    const artSize = 108.0;
    final uri = Uri.tryParse(url);
    final image = uri != null && uri.scheme == 'file'
        ? Image.file(
            File.fromUri(uri),
            width: artSize,
            height: artSize,
            fit: BoxFit.cover,
          )
        : Image.network(
            url,
            width: artSize,
            height: artSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _AlbumArtFallback(size: artSize);
            },
          );

    return ClipRRect(borderRadius: BorderRadius.circular(10), child: image);
  }
}

class _AlbumArtFallback extends StatelessWidget {
  const _AlbumArtFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.secondary.withValues(alpha: 0.6),
      child: Icon(Icons.album_rounded, color: theme.colorScheme.onSurface),
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

class _ScrollingText extends StatefulWidget {
  const _ScrollingText({required this.text, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<_ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<_ScrollingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(double overflow) {
    if (overflow <= 0) return;
    _controller.duration = Duration(
      milliseconds: (overflow * 20).round().clamp(2000, 8000),
    );
    _controller.forward();
  }

  void _onExit() {
    _controller.animateTo(
      0.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

        if (tp.width <= maxWidth) {
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
          );
        }

        final overflow = tp.width - maxWidth;
        const fadeWidth = 24.0;
        final leftStop = (fadeWidth / maxWidth).clamp(0.0, 0.49);
        final rightStop = (1.0 - fadeWidth / maxWidth).clamp(0.51, 1.0);

        return MouseRegion(
          onEnter: (_) => _onEnter(overflow),
          onExit: (_) => _onExit(),
          child: SizedBox(
            height: tp.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                final offset = t * overflow;
                final leftAlpha = (offset / fadeWidth).clamp(0.0, 1.0);
                final rightAlpha =
                    ((overflow - offset) / fadeWidth).clamp(0.0, 1.0);
                return ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 1.0 - leftAlpha),
                      Colors.white,
                      Colors.white,
                      Colors.white.withValues(alpha: 1.0 - rightAlpha),
                    ],
                    stops: [0.0, leftStop, rightStop, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: ClipRect(
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: double.infinity,
                      minHeight: tp.height,
                      maxHeight: tp.height,
                      alignment: Alignment.topLeft,
                      child: Transform.translate(
                        offset: Offset(-offset, 0),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                widget.text,
                style: widget.style,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        );
      },
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
