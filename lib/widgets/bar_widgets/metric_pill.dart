import 'package:flutter/material.dart';

class TopBarMetricPill extends StatelessWidget {
  const TopBarMetricPill({
    super.key,
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
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
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
        ],
      ),
    );
  }
}
