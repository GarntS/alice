import 'dart:io';

import 'package:flutter/material.dart';

import '../../rust_gen/state.dart';

class NotificationCard extends StatefulWidget {
  const NotificationCard({
    super.key,
    required this.notification,
    required this.onDismiss,
    required this.onInvokeAction,
    this.onBodyTap,
  });

  final NotificationSnapshot notification;
  final VoidCallback onDismiss;
  final void Function(String key) onInvokeAction;
  final VoidCallback? onBodyTap;

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.notification;
    final body = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _NotificationIcon(notification: n),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n.appName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatTimestamp(n.receivedAtUnixSecs),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            n.summary,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              n.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ],
          if (n.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (n.actions.length == 1)
                  _ActionButton(
                    label: n.actions[0].label,
                    onPressed: () => widget.onInvokeAction(n.actions[0].key),
                  )
                else
                  _SplitActionButton(
                    actions: n.actions,
                    onInvokeAction: widget.onInvokeAction,
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    final card = widget.onBodyTap == null
        ? body
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBodyTap,
            child: body,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (_hovered)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatTimestamp(BigInt unixSecs) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final delta = now - unixSecs.toInt();
  if (delta < 86400) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs.toInt() * 1000);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${delta ~/ 86400}d ago';
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.notification});

  final NotificationSnapshot notification;

  @override
  Widget build(BuildContext context) {
    final n = notification;

    if (n.imageData != null) {
      return Image.memory(
        n.imageData!,
        width: 24,
        height: 24,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    final imagePath = n.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final path = imagePath.startsWith('file://')
          ? Uri.parse(imagePath).toFilePath()
          : imagePath;
      if (path.startsWith('/')) {
        return Image.file(
          File(path),
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _tryAppIcon(n.appIcon),
        );
      }
    }

    return _tryAppIcon(n.appIcon);
  }

  Widget _tryAppIcon(String appIcon) {
    if (appIcon.startsWith('/') || appIcon.startsWith('file://')) {
      final path = appIcon.startsWith('file://')
          ? Uri.parse(appIcon).toFilePath()
          : appIcon;
      return Image.file(
        File(path),
        width: 24,
        height: 24,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return const Icon(Icons.notifications_rounded, size: 24);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

class _SplitActionButton extends StatelessWidget {
  const _SplitActionButton({
    required this.actions,
    required this.onInvokeAction,
  });

  final List<NotificationActionSnapshot> actions;
  final void Function(String key) onInvokeAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = actions[0];
    final overflow = actions.sublist(1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onInvokeAction(primary.key),
            child: Container(
              color: theme.colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                primary.label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          PopupMenuButton<String>(
            onSelected: onInvokeAction,
            padding: EdgeInsets.zero,
            itemBuilder: (_) => overflow
                .map(
                  (a) => PopupMenuItem<String>(
                    value: a.key,
                    height: 36,
                    child: Text(a.label, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            child: Container(
              color: theme.colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
