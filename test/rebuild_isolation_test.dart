import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets('panel highlight changes rebuild only affected consumers', (
    tester,
  ) async {
    final controller = PanelController();
    final state = testSnapshotState();
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    final counts = <String, int>{};
    await _pumpTopBar(tester, state, controller, counts);
    counts.clear();

    controller.toggle(
      AlicePanel.media,
      const PanelAnchor(
        globalPosition: Offset.zero,
        alignment: PanelAlignment.center,
      ),
    );
    await tester.pump();
    expect(counts, {'media': 1});

    counts.clear();
    controller.toggle(
      AlicePanel.clock,
      const PanelAnchor(
        globalPosition: Offset.zero,
        alignment: PanelAlignment.center,
      ),
    );
    await tester.pump();
    expect(counts, {'media': 1, 'clock': 1});
  });

  testWidgets('CPU-only snapshot update rebuilds only CPU top-bar consumer', (
    tester,
  ) async {
    final controller = PanelController();
    final snapshot = testSnapshot();
    final state = testSnapshotState(snapshot: snapshot);
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    final counts = <String, int>{};
    await _pumpTopBar(tester, state, controller, counts);
    counts.clear();

    state.ingest(copyTestSnapshot(snapshot, cpuUsageCores: 4.2));
    await tester.pump();

    expect(counts, {'cpu': 1});
  });

  testWidgets(
    'media, clock, tray, and notification updates rebuild only consumers',
    (tester) async {
      final controller = PanelController();
      var snapshot = testSnapshot();
      final state = testSnapshotState(snapshot: snapshot);
      addTearDown(controller.dispose);
      addTearDown(state.dispose);
      final counts = <String, int>{};
      await _pumpTopBar(tester, state, controller, counts);

      counts.clear();
      snapshot = copyTestSnapshot(
        snapshot,
        media: testMedia(albumTitle: 'Changed'),
      );
      state.ingest(snapshot);
      await tester.pump();
      expect(counts, {'media': 1});

      counts.clear();
      snapshot = copyTestSnapshot(
        snapshot,
        clock: const ClockSnapshot(
          timeZoneCode: 'UTC',
          dateLabel: '10 Mar',
          timeLabel: '13:38',
        ),
      );
      state.ingest(snapshot);
      await tester.pump();
      expect(counts, {'clock': 1});

      counts.clear();
      snapshot = copyTestSnapshot(snapshot, trayItems: testTrayItems(6));
      state.ingest(snapshot);
      await tester.pump();
      expect(counts, {'trayOverflow': 1});

      counts.clear();
      final notifications = [
        for (final n in snapshot.notifications)
          NotificationSnapshot(
            id: n.id,
            appName: n.appName,
            appIcon: n.appIcon,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            actions: n.actions,
            category: n.category,
            isRead: false,
            receivedAtUnixSecs: n.receivedAtUnixSecs,
            imageData: n.imageData,
            imagePath: n.imagePath,
          ),
      ];
      snapshot = copyTestSnapshot(snapshot, notifications: notifications);
      state.ingest(snapshot);
      await tester.pump();
      expect(counts, {'notifications': 1});
    },
  );

  testWidgets(
    'notification content change without unread count does not rebuild badge',
    (tester) async {
      final controller = PanelController();
      final snapshot = testSnapshot(notifications: testNotifications(2));
      final state = testSnapshotState(snapshot: snapshot);
      addTearDown(controller.dispose);
      addTearDown(state.dispose);
      final counts = <String, int>{};
      await _pumpTopBar(tester, state, controller, counts);
      counts.clear();

      final notifications = [
        for (final n in snapshot.notifications)
          n.id == 1
              ? NotificationSnapshot(
                  id: n.id,
                  appName: n.appName,
                  appIcon: n.appIcon,
                  summary: '${n.summary} updated',
                  body: n.body,
                  urgency: n.urgency,
                  actions: n.actions,
                  category: n.category,
                  isRead: n.isRead,
                  receivedAtUnixSecs: n.receivedAtUnixSecs,
                  imageData: n.imageData,
                  imagePath: n.imagePath,
                )
              : n,
      ];
      state.ingest(copyTestSnapshot(snapshot, notifications: notifications));
      await tester.pump();

      expect(counts, isNot(contains('notifications')));
    },
  );

  testWidgets('equivalent list instances do not rebuild list consumers', (
    tester,
  ) async {
    final controller = PanelController();
    final snapshot = testSnapshot();
    final state = testSnapshotState(snapshot: snapshot);
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    final counts = <String, int>{};
    await _pumpTopBar(tester, state, controller, counts);
    counts.clear();

    state.ingest(testSnapshot());
    await tester.pump();

    expect(counts, isEmpty);
  });
}

Future<void> _pumpTopBar(
  WidgetTester tester,
  AliceSnapshotState state,
  PanelController controller,
  Map<String, int> counts,
) async {
  await pumpAliceWidget(
    tester,
    SizedBox(
      width: 1200,
      height: 80,
      child: TopBar(
        config: testConfig(maxVisibleTrayItems: 3),
        snapshotState: state,
        panelController: controller,
        onWorkspaceTap: (_) {},
        onTrayItemTap: (_) {},
        onBackgroundTap: () {},
        onModuleBuild: (name) => counts[name] = (counts[name] ?? 0) + 1,
      ),
    ),
    size: const Size(1300, 120),
  );
}
