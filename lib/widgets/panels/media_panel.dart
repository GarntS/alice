import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../rust_gen/state.dart';
import 'panel_shell.dart';

class MediaPanel extends StatefulWidget {
  const MediaPanel({
    super.key,
    required this.media,
    required this.onAction,
    required this.onSeek,
  });

  final MediaSnapshot? media;
  final Future<void> Function(String) onAction;
  final Future<void> Function(int) onSeek;

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> {
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
      return const PanelShell(
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
                padding: const EdgeInsets.only(top: 6, left: 6),
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
        ? (_dragValue ?? (media.positionMicros / media.lengthMicros)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final positionLabel = _dragValue != null && canSeek
        ? _formatMicros((_dragValue! * media.lengthMicros).round())
        : media.positionLabel;

    return PanelShell(
      title: null,
      crossAxisAlignment: CrossAxisAlignment.center,
      titleAlign: TextAlign.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Text(positionLabel, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(media.lengthLabel, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: sliderValue,
              onChanged: canSeek ? (v) => setState(() => _dragValue = v) : null,
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
          onEnter: (_) {
            if (overflow <= 0) return;
            _controller.duration = Duration(
              milliseconds: (overflow * 20).round().clamp(2000, 8000),
            );
            _controller.forward();
          },
          onExit: (_) {
            _controller.animateTo(
              0.0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          },
          child: SizedBox(
            height: tp.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                final offset = t * overflow;
                final leftAlpha = (offset / fadeWidth).clamp(0.0, 1.0);
                final rightAlpha = ((overflow - offset) / fadeWidth).clamp(
                  0.0,
                  1.0,
                );
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
