import 'dart:typed_data';

import 'package:alicebar/widgets/panels/clock_panel.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/widgets/panels/media_panel.dart';
import 'package:alicebar/widgets/panels/panel_host.dart';
import 'package:alicebar/widgets/panels/panel_spec.dart';
import 'package:alicebar/widgets/panels/notification_panel.dart';
import 'package:alicebar/widgets/panels/power_panel.dart';
import 'package:alicebar/widgets/panels/tray_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  test('media panel size follows available content', () {
    final config = testConfig();

    expect(
      alicePanelSize(
        AlicePanel.media,
        config: config,
        snapshot: testSnapshot(media: null),
      ).height,
      84,
    );
    expect(
      alicePanelSize(
        AlicePanel.media,
        config: config,
        snapshot: testSnapshot(media: testMedia(artUrl: '')),
      ).height,
      228,
    );
    expect(
      alicePanelSize(
        AlicePanel.media,
        config: config,
        snapshot: testSnapshot(media: testMedia(artUrl: 'file:///tmp/art.png')),
      ).height,
      268,
    );
  });

  testWidgets(
    'media panel card keeps fixed width but sizes height to content',
    (tester) async {
      final snapshot = testSnapshot(media: testMedia(artUrl: ''));

      await pumpAliceWidget(
        tester,
        AlicePanelCard(
          panel: AlicePanel.media,
          config: testConfig(),
          snapshot: snapshot,
          onPowerAction: (_) async {},
          onMediaAction: (_) async {},
          onSeekMedia: (_) async {},
          onTrayAction: (_) async {},
          onDismissNotification: (_) async {},
          onDismissAllNotifications: () async {},
          onMarkAllNotificationsRead: () async {},
          onInvokeNotificationAction: (_, __) async {},
        ),
      );

      final cardSize = tester.getSize(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.padding == const EdgeInsets.all(16),
        ),
      );

      expect(cardSize.width, 360);
      expect(
        cardSize.height,
        lessThan(
          alicePanelSize(
            AlicePanel.media,
            config: testConfig(),
            snapshot: snapshot,
          ).height,
        ),
      );
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    },
  );

  testWidgets('media panel renders empty and populated states', (tester) async {
    final actions = <String>[];
    final seeks = <int>[];

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 380,
        height: 300,
        child: MediaPanel(
          media: null,
          onAction: (a) async => actions.add(a),
          onSeek: (p) async => seeks.add(p),
        ),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('No active MPRIS player.'), findsOneWidget);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 380,
        height: 300,
        child: MediaPanel(
          media: testMedia(lengthMicros: 0),
          onAction: (a) async => actions.add(a),
          onSeek: (p) async => seeks.add(p),
        ),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('A Very Testable Song'), findsOneWidget);
    expect(find.text('Alice Artist'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(actions, contains('playPause'));
  });

  testWidgets('tray, notifications, and power panels render edge cases', (
    tester,
  ) async {
    final trayTaps = <String>[];
    final powerActions = <String>[];
    final notificationActions = <String>[];
    final dismissed = <int>[];
    var clearAll = 0;
    var markRead = 0;

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 340,
        height: 340,
        child: TrayPanel(
          trayItems: testTrayItems(5, iconBytes: Uint8List.fromList([1, 2, 3])),
          maxVisibleTrayItems: 3,
          onTrayAction: (item) async => trayTaps.add(item.id),
        ),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('Tray Overflow'), findsOneWidget);
    expect(find.text('Tray Item 2'), findsOneWidget);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 420,
        height: 500,
        child: NotificationPanel(
          notifications: testNotifications(
            3,
            imageData: Uint8List.fromList([9, 8, 7]),
          ),
          onDismissAll: () => clearAll++,
          onDismissOne: dismissed.add,
          onMarkAllRead: () => markRead++,
          onInvokeAction: (id, key) => notificationActions.add('$id:$key'),
        ),
      ),
    );
    await tester.pump();
    expectNoFlutterErrors();
    expect(markRead, 1);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Summary 0'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(clearAll, 1);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 300,
        height: 320,
        child: PowerPanel(onAction: (action) async => powerActions.add(action)),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('Power Off'), findsOneWidget);
    await tester.tap(find.text('Lock'));
    await tester.pump();
    expect(powerActions, contains('lock'));
  });

  testWidgets('calendar widget changes dates without native calendar calls', (
    tester,
  ) async {
    final selected = <DateTime>[];

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 360,
        child: AliceCalendar(
          selectedDate: DateTime(2026, 5, 16),
          indicators: {
            '2026-05-16': [Colors.green, Colors.blue],
          },
          onDateSelected: selected.add,
          onMonthChanged: (_, __) {},
        ),
      ),
    );

    expectNoFlutterErrors();
    expect(find.textContaining('May', findRichText: true), findsOneWidget);
    await tester.tap(find.text('17'));
    await tester.pump();
    expect(selected.last.day, 17);
  });
}
