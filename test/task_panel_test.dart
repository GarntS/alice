import 'dart:async';

import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:alicebar/widgets/panels/task_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  final today = DateTime(2026, 7, 20, 12);

  testWidgets(
    'renders all sections, priorities, sources, dates, and scroll bounds',
    (tester) async {
      final completedToday = today.toUtc().millisecondsSinceEpoch ~/ 1000;
      final tasks = [
        task('overdue', due: '2026-07-19', priority: TaskPriority.doNow),
        task('today', due: '2026-07-20', priority: TaskPriority.urgent),
        task('future', due: '2026-07-21', priority: TaskPriority.high),
        task('other-year', due: '2027-01-02', priority: TaskPriority.medium),
        task('undated', due: null, priority: TaskPriority.low),
        task(
          'completed-today',
          status: TaskStatus.completed,
          completed: completedToday,
        ),
        task(
          'completed-old',
          status: TaskStatus.completed,
          completed: completedToday - const Duration(days: 1).inSeconds,
        ),
        ...List.generate(25, (index) => task('long-$index', due: null)),
      ];
      await pumpPanel(tester, tasks: tasks, now: () => today);

      for (final label in ['Do Now', 'Urgent', 'High', 'Medium', 'Low']) {
        expect(find.text(label), findsWidgets);
      }
      final theme = Theme.of(
        tester.element(find.byKey(const ValueKey('task-panel'))),
      );
      final priorityColors = <String, Color>{
        'doNow': theme.colorScheme.error,
        'urgent': theme.colorScheme.error,
        'high': Colors.orange,
        'medium': Colors.green,
        'low': Colors.blue,
      };
      for (final entry in priorityColors.entries) {
        final labels = tester.widgetList<Text>(
          find.byKey(ValueKey('task-priority-${entry.key}')),
        );
        expect(labels.first.style?.color, entry.value);
      }
      final checkbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('task-checkbox-overdue')),
      );
      expect(checkbox.side?.width, 1.15);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('task-title-overdue')))
            .style
            ?.fontWeight,
        FontWeight.w500,
      );
      expect(find.text('19 July'), findsOneWidget);
      expect(find.text('Today - 20 July'), findsOneWidget);
      expect(find.text('21 July'), findsOneWidget);
      expect(find.text('2 January 2027'), findsOneWidget);
      expect(find.text('No due date'), findsOneWidget);
      expect(find.text('completed-old'), findsNothing);
      expect(find.textContaining('12:00'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -1800));
      await tester.pump();
      expect(find.text('Completed today'), findsOneWidget);
      expect(find.text('Project long-24'), findsOneWidget);
      expectNoFlutterErrors();
    },
  );

  testWidgets('uses flat typographic hierarchy and keeps sync time in footer', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      tasks: [task('styled')],
      sync: const CalDavSyncState(
        freshness: CalDavFreshness.current,
        lastSuccessUnixSecs: 100,
        hasCachedData: true,
      ),
      now: () => today,
    );

    final context = tester.element(find.byKey(const ValueKey('task-panel')));
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('task-panel-title')))
          .style
          ?.color,
      primary,
    );
    final sectionTitle = tester.widget<Text>(find.text('Today - 20 July'));
    expect(sectionTitle.style?.color, colors.onSurface);
    expect(sectionTitle.style?.fontSize, 15);
    expect(sectionTitle.style?.fontWeight, FontWeight.w700);
    final titleSpans = (sectionTitle.textSpan! as TextSpan).children!;
    expect(titleSpans[1].toPlainText(), 'July');
    expect(titleSpans[1].style?.color, primary);
    expect(titleSpans[1].style?.fontWeight, FontWeight.w700);
    final sectionLabel = find.byKey(
      const ValueKey('task-section-label-today-2026-07-20 00:00:00.000'),
    );
    final summary = find.byKey(const ValueKey('task-panel-summary'));
    final row = find.byKey(const ValueKey('task-row-styled'));
    final priority = find.byKey(const ValueKey('task-priority-high'));
    expect(tester.widget(summary), isA<Padding>());
    expect(tester.getSize(summary).height, lessThan(30));
    expect(
      find.descendant(of: summary, matching: find.byType(AliceIcon)),
      findsNWidgets(3),
    );
    final activeSummary = tester.widget<Text>(
      find.byKey(const ValueKey('task-summary-active')),
    );
    expect(activeSummary.textSpan!.toPlainText(), '1 Active');
    final activeSpans = (activeSummary.textSpan! as TextSpan).children!;
    expect(activeSpans[0].style?.color, primary);
    expect(activeSpans[1].style?.color, primary);
    final todaySummary = tester.widget<Text>(
      find.byKey(const ValueKey('task-summary-today')),
    );
    final todaySpans = (todaySummary.textSpan! as TextSpan).children!;
    expect(todaySpans[0].style?.color, colors.onSurface);
    expect(todaySpans[1].style?.color, colors.onSurface);
    final sectionPadding = tester.widget<Padding>(sectionLabel);
    expect(sectionPadding.padding, const EdgeInsets.fromLTRB(2, 9, 2, 4));
    expect(
      find.descendant(of: sectionLabel, matching: find.byType(Icon)),
      findsNothing,
    );
    final sectionCount = find.descendant(
      of: sectionLabel,
      matching: find.text('1 task'),
    );
    expect(
      (tester.getCenter(find.text('Today - 20 July')).dy -
              tester.getCenter(sectionCount).dy)
          .abs(),
      lessThan(0.5),
    );
    expect(tester.widget(row), isA<Padding>());
    expect(tester.widget(priority), isA<Text>());

    final footer = find.byKey(const ValueKey('task-panel-last-success'));
    expect(
      tester.getTopLeft(footer).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(row).dy),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('task-panel'))).height,
      lessThan(700),
    );
  });

  testWidgets(
    'shows current empty, loading, stale cache, and sync error states',
    (tester) async {
      await pumpPanel(
        tester,
        sync: const CalDavSyncState(
          freshness: CalDavFreshness.current,
          hasCachedData: false,
        ),
        now: () => today,
      );
      expect(find.byKey(const ValueKey('task-panel-empty')), findsOneWidget);

      await pumpPanel(
        tester,
        sync: const CalDavSyncState(
          freshness: CalDavFreshness.loading,
          hasCachedData: false,
        ),
        now: () => today,
      );
      expect(find.byKey(const ValueKey('task-panel-loading')), findsOneWidget);

      await pumpPanel(
        tester,
        tasks: [task('cached')],
        sync: const CalDavSyncState(
          freshness: CalDavFreshness.stale,
          lastSuccessUnixSecs: 100,
          hasCachedData: true,
        ),
        now: () => today,
      );
      expect(find.byKey(const ValueKey('task-panel-stale')), findsOneWidget);
      expect(find.text('cached'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-panel-last-success')),
        findsOneWidget,
      );

      await pumpPanel(
        tester,
        tasks: [task('cached')],
        sync: const CalDavSyncState(
          freshness: CalDavFreshness.error,
          error: 'redacted synchronization error',
          hasCachedData: true,
        ),
        now: () => today,
      );
      expect(
        find.byKey(const ValueKey('task-panel-sync-error')),
        findsOneWidget,
      );
      expect(find.text('cached'), findsOneWidget);
    },
  );

  testWidgets('refreshes on open/manual and coalesces pending UI requests', (
    tester,
  ) async {
    var calls = 0;
    Completer<void>? pending;
    await pumpPanel(
      tester,
      now: () => today,
      onRefresh: () {
        calls++;
        if (calls == 1) return Future.value();
        pending = Completer<void>();
        return pending!.future;
      },
    );
    expect(calls, 1, reason: 'panel-open refresh');

    await tester.tap(find.byKey(const ValueKey('task-panel-refresh')));
    await tester.pump();
    expect(calls, 2);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('task-panel-refresh')))
          .onPressed,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('task-panel-refresh')),
      warnIfMissed: false,
    );
    expect(calls, 2);
    pending!.complete();
    await tester.pump();
  });

  testWidgets(
    'optimistic completion moves immediately and failure rolls back',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await pumpPanel(
        tester,
        tasks: [task('toggle')],
        now: () => today,
        onCompletion: (_, __) {
          calls++;
          return completion.future;
        },
      );
      await tester.tap(find.byKey(const ValueKey('task-checkbox-toggle')));
      await tester.pump();
      expect(find.text('Completed today'), findsOneWidget);
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completion.complete();
      await tester.pump();
      expect(find.text('Completed today'), findsOneWidget);

      await pumpPanel(
        tester,
        tasks: [task('failure')],
        now: () => today,
        onCompletion: (_, __) => Future.error(Exception('write failed')),
      );
      await tester.tap(find.byKey(const ValueKey('task-checkbox-failure')));
      await tester.pumpAndSettle();
      expect(find.text('Completed today'), findsNothing);
      expect(find.text('Today - 20 July'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('task-panel-action-error')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'un-completion moves back and non-checkbox row areas do nothing',
    (tester) async {
      final completed = today.toUtc().millisecondsSinceEpoch ~/ 1000;
      bool? requested;
      var calls = 0;
      await pumpPanel(
        tester,
        tasks: [
          task('undo', status: TaskStatus.completed, completed: completed),
        ],
        now: () => today,
        onCompletion: (_, value) async {
          calls++;
          requested = value;
        },
      );
      expect(find.text('Completed today'), findsOneWidget);
      await tester.tap(find.text('undo'));
      await tester.pump();
      expect(calls, 0, reason: 'only checkbox is interactive');

      await tester.tap(find.byKey(const ValueKey('task-checkbox-undo')));
      await tester.pump();
      expect(requested, isFalse);
      expect(calls, 1);
      expect(find.text('Today - 20 July'), findsOneWidget);
    },
  );

  testWidgets(
    'local-date rollover updates section membership without new tasks',
    (tester) async {
      var now = DateTime(2026, 7, 20, 23, 59);
      final key = GlobalKey<TaskPanelState>();
      await pumpPanel(
        tester,
        key: key,
        tasks: [task('tomorrow', due: '2026-07-21')],
        now: () => now,
      );
      expect(find.text('21 July'), findsOneWidget);
      expect(find.text('Today - 21 July'), findsNothing);
      now = DateTime(2026, 7, 21);
      key.currentState!.refreshLocalDate();
      await tester.pump();
      expect(find.text('Today - 21 July'), findsOneWidget);
    },
  );
}

Future<void> pumpPanel(
  WidgetTester tester, {
  Key? key,
  List<NormalizedTask> tasks = const [],
  CalDavSyncState sync = const CalDavSyncState(
    freshness: CalDavFreshness.current,
    hasCachedData: true,
  ),
  DateTime Function()? now,
  Future<void> Function()? onRefresh,
  Future<void> Function(TaskResourceIdentity, bool)? onCompletion,
}) => pumpAliceWidget(
  tester,
  Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 348, maxHeight: 700),
      child: TaskPanel(
        key: key,
        tasks: tasks,
        syncState: sync,
        now: now,
        scheduleDateRollover: false,
        onRefresh: onRefresh ?? () async {},
        onCompletion: onCompletion ?? (_, __) async {},
      ),
    ),
  ),
  size: const Size(420, 780),
);

NormalizedTask task(
  String id, {
  String? due = '2026-07-20',
  TaskStatus status = TaskStatus.active,
  TaskPriority priority = TaskPriority.high,
  int? completed,
}) => NormalizedTask(
  identity: TaskResourceIdentity(
    collectionHref: 'https://example.test/tasks/',
    resourceHref: id,
  ),
  uid: id,
  title: id,
  collectionName: 'Project $id',
  dueDate: due,
  completedAtUnixSecs: completed,
  status: status,
  priority: priority,
);
