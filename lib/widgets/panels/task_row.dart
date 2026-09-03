import 'package:material_ui/material_ui.dart';

import '../../rust_gen/caldav/models.dart';
import '../alice_icon.dart';

class CalDavTaskRow extends StatelessWidget {
  const CalDavTaskRow({
    super.key,
    required this.task,
    required this.completed,
    required this.pending,
    required this.onChanged,
  });

  final NormalizedTask task;
  final bool completed;
  final bool pending;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final foreground = completed
        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
        : theme.colorScheme.onSurface;
    return Semantics(
      label:
          '${task.title}, ${task.collectionName}, ${taskPriorityLabel(task.priority)}',
      container: true,
      child: Padding(
        key: ValueKey('task-row-${task.identity.resourceHref}'),
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              height: 36,
              child: pending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Checkbox(
                      key: ValueKey(
                        'task-checkbox-${task.identity.resourceHref}',
                      ),
                      side: BorderSide(
                        width: 1.15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      value: completed,
                      onChanged: onChanged == null
                          ? null
                          : (value) => onChanged!(value ?? completed),
                      semanticLabel: completed
                          ? 'Mark ${task.title} incomplete'
                          : 'Mark ${task.title} complete',
                    ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    key: ValueKey('task-title-${task.identity.resourceHref}'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                      decoration: completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TaskPriorityChip(priority: task.priority),
                      const SizedBox(width: 7),
                      AliceIcon(
                        AliceIcons.folder,
                        size: 12,
                        color: muted.withValues(alpha: completed ? 0.45 : 0.7),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          task.collectionName,
                          key: ValueKey(
                            'task-source-${task.identity.resourceHref}',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted.withValues(
                              alpha: completed ? 0.55 : 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskPriorityChip extends StatelessWidget {
  const TaskPriorityChip({super.key, required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = taskPriorityColor(context, priority);
    return Text(
      taskPriorityLabel(priority),
      key: ValueKey('task-priority-${priority.name}'),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

String taskPriorityLabel(TaskPriority priority) => switch (priority) {
  TaskPriority.doNow => 'Do Now',
  TaskPriority.urgent => 'Urgent',
  TaskPriority.high => 'High',
  TaskPriority.medium => 'Medium',
  TaskPriority.low => 'Low',
};

Color taskPriorityColor(BuildContext context, TaskPriority priority) {
  final colors = Theme.of(context).colorScheme;
  return switch (priority) {
    TaskPriority.doNow || TaskPriority.urgent => colors.error,
    TaskPriority.high => Colors.orange,
    TaskPriority.medium => Colors.green,
    TaskPriority.low => Colors.blue,
  };
}
