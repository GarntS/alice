import 'package:alicebar/alice_config.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/widgets/panels/panel_host.dart';
import 'package:alicebar/widgets/panels/panel_sizes.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

const caldavConfig = CalDavConfig(
  principalUrl: 'https://example.test/dav/principals/alice/',
  allowHttp: false,
  username: 'alice',
  collectionHrefs: ['https://example.test/dav/projects/1'],
  pollIntervalSecs: 60,
  caCertificatePath: null,
);

void main() {
  test('tasks panel identity and maximum scrollable size are canonical', () {
    expect(alicePanelFromId('tasks'), AlicePanel.tasks);
    expect(AlicePanel.tasks.id, 'tasks');
    expect(alicePanelSize(AlicePanel.tasks), const Size(380, 800));
  });

  testWidgets('task panel card fits short content below its maximum height', (
    tester,
  ) async {
    final snapshot = testSnapshot(
      tasks: [
        NormalizedTask(
          identity: const TaskResourceIdentity(
            collectionHref: 'https://example.test/dav/projects/1',
            resourceHref: 'https://example.test/dav/projects/1/one.ics',
          ),
          uid: 'one',
          title: 'One task',
          collectionName: 'Work',
          dueDate: _todayKey(),
          status: TaskStatus.active,
          priority: TaskPriority.high,
        ),
      ],
      caldavSyncState: const CalDavSyncState(
        freshness: CalDavFreshness.current,
        lastSuccessUnixSecs: 100,
        hasCachedData: true,
      ),
    );

    await pumpAliceWidget(
      tester,
      AlicePanelCard(
        panel: AlicePanel.tasks,
        config: testConfig(caldav: caldavConfig),
        snapshotState: testSnapshotState(
          config: testConfig(caldav: caldavConfig),
          snapshot: snapshot,
        ),
        onPowerAction: (_) async {},
        onMediaAction: (_) async {},
        onSeekMedia: (_) async {},
        onTrayAction: (_) async {},
        onDismissNotification: (_) async {},
        onDismissAllNotifications: () async {},
        onMarkAllNotificationsRead: () async {},
        onInvokeNotificationAction: (_, __) async {},
        onTaskRefresh: () async {},
        onTaskCompletion: (_, __) async {},
      ),
    );

    final cardSize = tester.getSize(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.padding == const EdgeInsets.fromLTRB(16, 12, 16, 16),
      ),
    );
    expect(cardSize.width, 380);
    expect(cardSize.height, lessThan(alicePanelSize(AlicePanel.tasks).height));
    expectNoFlutterErrors();
  });

  testWidgets('configured task module is immediately before clock', (
    tester,
  ) async {
    final controller = PanelController();
    addTearDown(controller.dispose);
    final modules = <String>[];
    final state = testSnapshotState(
      config: testConfig(caldav: caldavConfig),
      snapshot: testSnapshot(
        tasks: [
          NormalizedTask(
            identity: const TaskResourceIdentity(
              collectionHref: 'https://example.test/tasks/',
              resourceHref: 'https://example.test/tasks/1.ics',
            ),
            uid: 'one',
            title: 'One',
            collectionName: 'Tasks',
            dueDate: _todayKey(),
            status: TaskStatus.active,
            priority: TaskPriority.high,
          ),
        ],
      ),
    );

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1600,
        child: TopBar(
          config: testConfig(caldav: caldavConfig),
          snapshotState: state,
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
          onModuleBuild: modules.add,
        ),
      ),
      size: const Size(1700, 120),
    );
    expectNoFlutterErrors();
    expect(modules, contains('tasks'));
    expect(modules.indexOf('tasks') + 1, modules.indexOf('clock'));

    final baselineTaskBuilds = modules.where((name) => name == 'tasks').length;
    controller.toggle(
      AlicePanel.media,
      const PanelAnchor(
        globalPosition: Offset.zero,
        alignment: PanelAlignment.center,
      ),
    );
    await tester.pump();
    expect(modules.where((name) => name == 'tasks').length, baselineTaskBuilds);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^Tasks,')));
    await tester.pump();
    expect(controller.openPanel, AlicePanel.tasks);
    expect(controller.anchor?.alignment, PanelAlignment.right);
    expect(
      modules.where((name) => name == 'tasks').length,
      baselineTaskBuilds + 1,
    );
  });

  testWidgets('task module is omitted without valid CalDAV config', (
    tester,
  ) async {
    final controller = PanelController();
    addTearDown(controller.dispose);
    final modules = <String>[];
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 700,
        child: TopBar(
          config: testConfig(),
          snapshotState: testSnapshotState(),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
          onModuleBuild: modules.add,
        ),
      ),
      size: const Size(740, 120),
    );
    expectNoFlutterErrors();
    expect(modules, isNot(contains('tasks')));
    expect(find.bySemanticsLabel(RegExp(r'^Tasks,')), findsNothing);
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
