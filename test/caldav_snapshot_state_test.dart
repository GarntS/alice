import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  test(
    'task and synchronization slices compare complete content independently',
    () {
      final state = AliceSnapshotState(config: testConfig());
      addTearDown(state.dispose);
      var taskNotifications = 0;
      var syncNotifications = 0;
      state.tasks.addListener(() => taskNotifications++);
      state.caldavSyncState.addListener(() => syncNotifications++);

      final task = testTask();
      state.ingest(
        testSnapshot(tasks: [task], caldavSyncState: currentSyncState),
      );
      expect(taskNotifications, 1);
      expect(syncNotifications, 1);
      expect(state.currentTasks.single.title, 'Task one');
      expect(state.currentCalDavSyncState.freshness, CalDavFreshness.current);

      state.ingest(
        testSnapshot(tasks: [testTask()], caldavSyncState: currentSyncState),
      );
      expect(taskNotifications, 1, reason: 'equivalent fresh list is stable');
      expect(syncNotifications, 1);

      state.ingest(
        testSnapshot(
          tasks: [testTask(title: 'Renamed')],
          caldavSyncState: currentSyncState,
        ),
      );
      expect(taskNotifications, 2);
      expect(syncNotifications, 1);

      state.ingest(
        testSnapshot(
          tasks: [testTask(title: 'Renamed')],
          caldavSyncState: const CalDavSyncState(
            freshness: CalDavFreshness.error,
            error: 'redacted failure',
            hasCachedData: true,
          ),
        ),
      );
      expect(taskNotifications, 2);
      expect(syncNotifications, 2);
      expect(state.currentSnapshot.tasks.single.title, 'Renamed');
    },
  );

  test(
    'status-only changes notify tasks and counts, unrelated updates do not',
    () {
      final state = AliceSnapshotState(
        config: testConfig(),
        now: () => DateTime(2026, 7, 20),
      );
      addTearDown(state.dispose);
      var tasks = 0;
      var sync = 0;
      var today = 0;
      state.tasks.addListener(() => tasks++);
      state.caldavSyncState.addListener(() => sync++);
      state.dueTodayTaskCount.addListener(() => today++);

      final initial = testSnapshot(tasks: [testTask()]);
      state.ingest(initial);
      expect((tasks, sync, today), (1, 0, 1));

      state.ingest(
        copyTestSnapshot(
          initial,
          tasks: [testTask(status: TaskStatus.completed)],
        ),
      );
      expect((tasks, sync, today), (2, 0, 2));
      expect(state.currentDueTodayTaskCount, 0);

      state.ingest(
        copyTestSnapshot(
          state.currentSnapshot,
          cpuUsageCores: 7.5,
          memoryUsagePercent: 10,
        ),
      );
      expect((tasks, sync, today), (2, 0, 2));
    },
  );

  test('due projections notify independently and recompute at rollover', () {
    var now = DateTime(2026, 7, 20, 23, 59);
    final state = AliceSnapshotState(config: testConfig(), now: () => now);
    addTearDown(state.dispose);
    var todayNotifications = 0;
    var overdueNotifications = 0;
    state.dueTodayTaskCount.addListener(() => todayNotifications++);
    state.overdueTaskCount.addListener(() => overdueNotifications++);

    List<NormalizedTask> tasks({String overdueTitle = 'Task one'}) => [
      testTask(href: 'overdue', title: overdueTitle, dueDate: '2026-07-19'),
      testTask(href: 'today', dueDate: '2026-07-20'),
      testTask(href: 'future', dueDate: '2026-07-21'),
      testTask(href: 'undated', dueDate: null),
      testTask(
        href: 'completed',
        dueDate: '2026-07-19',
        status: TaskStatus.completed,
      ),
    ];

    state.ingest(testSnapshot(tasks: tasks()));
    expect(state.currentDueTodayTaskCount, 1);
    expect(state.currentOverdueTaskCount, 1);
    expect(todayNotifications, 1);
    expect(overdueNotifications, 1);

    state.ingest(testSnapshot(tasks: tasks(overdueTitle: 'Renamed')));
    expect(todayNotifications, 1, reason: 'title does not change counts');
    expect(overdueNotifications, 1);

    now = DateTime(2026, 7, 21);
    state.refreshTaskDateProjections();
    expect(state.currentDueTodayTaskCount, 1);
    expect(state.currentOverdueTaskCount, 2);
    expect(todayNotifications, 1, reason: 'today count stayed at one');
    expect(overdueNotifications, 2);
  });
}

final currentSyncState = CalDavSyncState(
  freshness: CalDavFreshness.current,
  lastSuccessUnixSecs: 42,
  hasCachedData: true,
);

NormalizedTask testTask({
  String href = '1.ics',
  String title = 'Task one',
  String? dueDate = '2026-07-20',
  TaskStatus status = TaskStatus.active,
}) => NormalizedTask(
  identity: TaskResourceIdentity(
    collectionHref: 'https://example.test/tasks/',
    resourceHref: 'https://example.test/tasks/$href',
  ),
  uid: href,
  title: title,
  collectionName: 'Tasks',
  dueDate: dueDate,
  status: status,
  priority: TaskPriority.high,
);
