import 'dart:collection';

import '../../rust_gen/caldav/models.dart';

enum TaskSectionKind { overdue, today, future, undated, completedToday }

class TaskSection {
  const TaskSection({
    required this.kind,
    required this.date,
    required this.tasks,
  });

  final TaskSectionKind kind;
  final DateTime? date;
  final List<NormalizedTask> tasks;
}

List<TaskSection> buildTaskSections(
  Iterable<NormalizedTask> tasks, {
  required DateTime today,
  DateTime Function(int unixSeconds)? completedAtLocal,
}) {
  final day = _dateOnly(today);
  final dated = SplayTreeMap<DateTime, List<NormalizedTask>>();
  final undated = <NormalizedTask>[];
  final completedToday = <NormalizedTask>[];
  final toLocal =
      completedAtLocal ??
      (seconds) => DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      ).toLocal();

  for (final task in tasks) {
    if (task.status == TaskStatus.cancelled) continue;
    if (task.status == TaskStatus.completed) {
      final completed = task.completedAtUnixSecs;
      if (completed != null && _dateOnly(toLocal(completed)) == day) {
        completedToday.add(task);
      }
      continue;
    }
    final due = task.dueDate == null ? null : DateTime.tryParse(task.dueDate!);
    if (due == null) {
      undated.add(task);
    } else {
      dated.putIfAbsent(_dateOnly(due), () => []).add(task);
    }
  }

  final sections = <TaskSection>[];
  for (final entry in dated.entries) {
    entry.value.sort(compareActiveTasks);
    sections.add(
      TaskSection(
        kind: entry.key.isBefore(day)
            ? TaskSectionKind.overdue
            : entry.key == day
            ? TaskSectionKind.today
            : TaskSectionKind.future,
        date: entry.key,
        tasks: List.unmodifiable(entry.value),
      ),
    );
  }
  if (undated.isNotEmpty) {
    undated.sort(compareActiveTasks);
    sections.add(
      TaskSection(
        kind: TaskSectionKind.undated,
        date: null,
        tasks: List.unmodifiable(undated),
      ),
    );
  }
  if (completedToday.isNotEmpty) {
    completedToday.sort(compareCompletedTasks);
    sections.add(
      TaskSection(
        kind: TaskSectionKind.completedToday,
        date: day,
        tasks: List.unmodifiable(completedToday),
      ),
    );
  }
  return List.unmodifiable(sections);
}

int compareActiveTasks(NormalizedTask left, NormalizedTask right) =>
    left.priority.index.compareTo(right.priority.index) != 0
    ? left.priority.index.compareTo(right.priority.index)
    : _compareTitleAndHref(left, right);

int compareCompletedTasks(NormalizedTask left, NormalizedTask right) {
  final completed = (right.completedAtUnixSecs ?? -1).compareTo(
    left.completedAtUnixSecs ?? -1,
  );
  return completed != 0 ? completed : compareActiveTasks(left, right);
}

String taskSectionHeader(TaskSection section, DateTime today) =>
    switch (section.kind) {
      TaskSectionKind.today =>
        'Today - ${formatShortTaskDate(section.date!, today)}',
      TaskSectionKind.undated => 'No due date',
      TaskSectionKind.completedToday => 'Completed today',
      TaskSectionKind.overdue ||
      TaskSectionKind.future => formatShortTaskDate(section.date!, today),
    };

String formatShortTaskDate(DateTime date, DateTime today) {
  final base = '${date.day} ${taskMonthName(date.month)}';
  return date.year == today.year ? base : '$base ${date.year}';
}

String taskMonthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];

int _compareTitleAndHref(NormalizedTask left, NormalizedTask right) {
  final title = left.title.toLowerCase().compareTo(right.title.toLowerCase());
  return title != 0
      ? title
      : left.identity.resourceHref.compareTo(right.identity.resourceHref);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
