import 'package:material_ui/material_ui.dart';

import 'panel_shell.dart';

class PowerPanel extends StatelessWidget {
  const PowerPanel({super.key, required this.onAction});

  final Future<void> Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
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
