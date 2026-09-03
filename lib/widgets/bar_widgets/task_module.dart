import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import '../../panel_controller.dart';
import '../../rust_gen/caldav/models.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarTaskModule extends StatelessWidget {
  const TopBarTaskModule({
    super.key,
    required this.dueTodayCount,
    required this.overdueCount,
    required this.syncState,
    required this.highlighted,
    required this.onToggle,
  });

  final int dueTodayCount;
  final int overdueCount;
  final CalDavSyncState syncState;
  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    final hasError = syncState.freshness == CalDavFreshness.error;
    final semantics = hasError
        ? 'Tasks, synchronization error'
        : 'Tasks, $dueTodayCount due today, $overdueCount overdue';
    return Semantics(
      label: semantics,
      button: true,
      excludeSemantics: true,
      child: TopBarPanelTapTarget(
        alignment: PanelAlignment.right,
        onTap: onToggle,
        child: TopBarPill(
          icon: AliceIcons.listChecks,
          label: '',
          highlighted: highlighted,
          labelWidget: hasError
              ? AliceIcon(
                  AliceIcons.warningCircle,
                  key: const ValueKey('task-module-error'),
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                )
              : dueTodayCount == 0 && overdueCount == 0
              ? null
              : _TaskCounts(
                  dueTodayCount: dueTodayCount,
                  overdueCount: overdueCount,
                ),
        ),
      ),
    );
  }
}

class _TaskCounts extends StatelessWidget {
  const _TaskCounts({required this.dueTodayCount, required this.overdueCount});

  final int dueTodayCount;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dueTodayCount > 0)
          _CountChip(
            key: const ValueKey('task-module-today'),
            label: '$dueTodayCount',
            color: Theme.of(context).colorScheme.primary,
          ),
        if (dueTodayCount > 0 && overdueCount > 0) const SizedBox(width: 4),
        if (overdueCount > 0)
          _CountChip(
            key: const ValueKey('task-module-overdue'),
            label: '$overdueCount',
            color: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.55)),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}
