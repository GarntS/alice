import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/widgets/panels/task_panel_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 20);

  test('groups dated, undated, and completed-today tasks in section order', () {
    final sections = buildTaskSections(
      [
        task('future', due: '2026-07-21'),
        task('today-low', due: '2026-07-20', priority: TaskPriority.low),
        task('overdue', due: '2026-07-19'),
        task('today-now', due: '2026-07-20', priority: TaskPriority.doNow),
        task('undated', due: null),
        task('completed-old', status: TaskStatus.completed, completed: 100),
        task('completed-new', status: TaskStatus.completed, completed: 200),
        task('cancelled', status: TaskStatus.cancelled),
      ],
      today: today,
      completedAtLocal: (seconds) => seconds >= 100
          ? DateTime(2026, 7, 20, 12, 0, seconds % 60)
          : DateTime(2026, 7, 19),
    );

    expect(sections.map((section) => section.kind), [
      TaskSectionKind.overdue,
      TaskSectionKind.today,
      TaskSectionKind.future,
      TaskSectionKind.undated,
      TaskSectionKind.completedToday,
    ]);
    expect(sections[1].tasks.map((task) => task.uid), [
      'today-now',
      'today-low',
    ]);
    expect(sections.last.tasks.map((task) => task.uid), [
      'completed-new',
      'completed-old',
    ]);
    expect(
      sections.expand((section) => section.tasks).map((task) => task.uid),
      isNot(contains('cancelled')),
    );
  });

  test('priority, case-insensitive title, and href are deterministic', () {
    final tasks = [
      task('b', title: 'alpha', priority: TaskPriority.high),
      task('a', title: 'ALPHA', priority: TaskPriority.high),
      task('urgent', priority: TaskPriority.urgent),
      task('medium', priority: TaskPriority.medium),
      task('low', priority: TaskPriority.low),
      task('now', priority: TaskPriority.doNow),
    ]..sort(compareActiveTasks);
    expect(tasks.map((task) => task.uid), [
      'now',
      'urgent',
      'a',
      'b',
      'medium',
      'low',
    ]);
  });

  test('full-month headers omit current year, include other year, and no time', () {
    expect(
      formatShortTaskDate(DateTime(2026, 7, 20, 23, 59), today),
      '20 July',
    );
    expect(
      formatShortTaskDate(DateTime(2025, 12, 1, 8, 30), today),
      '1 December 2025',
    );
    expect(
      taskSectionHeader(
        TaskSection(kind: TaskSectionKind.today, date: today, tasks: const []),
        today,
      ),
      'Today - 20 July',
    );
    expect(
      taskSectionHeader(
        const TaskSection(
          kind: TaskSectionKind.completedToday,
          date: null,
          tasks: [],
        ),
        today,
      ),
      'Completed today',
    );
  });
}

NormalizedTask task(
  String id, {
  String? due = '2026-07-20',
  String? title,
  TaskStatus status = TaskStatus.active,
  TaskPriority priority = TaskPriority.high,
  int? completed,
}) => NormalizedTask(
  identity: TaskResourceIdentity(
    collectionHref: 'https://example.test/tasks/',
    resourceHref: 'https://example.test/tasks/$id.ics',
  ),
  uid: id,
  title: title ?? id,
  collectionName: 'Tasks',
  dueDate: due,
  completedAtUnixSecs: completed,
  status: status,
  priority: priority,
);
