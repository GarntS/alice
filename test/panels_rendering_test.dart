import 'dart:typed_data';

import 'package:alicebar/alice_config.dart';
import 'package:alicebar/widgets/panels/clock_panel.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/widgets/panels/media_panel.dart';
import 'package:alicebar/widgets/panels/panel_host.dart';
import 'package:alicebar/widgets/panels/panel_sizes.dart';
import 'package:alicebar/widgets/panels/notification_panel.dart';
import 'package:alicebar/widgets/panels/power_panel.dart';
import 'package:alicebar/widgets/panels/tray_panel.dart';
import 'package:alicebar/widgets/panels/weather_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets(
    'media panel card keeps fixed width but sizes height to content',
    (tester) async {
      final snapshot = testSnapshot(media: testMedia(artUrl: ''));

      await pumpAliceWidget(
        tester,
        AlicePanelCard(
          panel: AlicePanel.media,
          config: testConfig(),
          snapshotState: testSnapshotState(snapshot: snapshot),
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
              widget is Container &&
              widget.padding == const EdgeInsets.fromLTRB(16, 12, 16, 16),
        ),
      );

      expect(cardSize.width, 360);
      expect(
        cardSize.height,
        lessThan(alicePanelSize(AlicePanel.media).height),
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

  testWidgets('weather panel renders no-data and populated states', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 340,
        height: 420,
        child: WeatherPanel(config: testConfig(), weather: null),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('Weather data unavailable.'), findsOneWidget);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 340,
        height: 520,
        child: WeatherPanel(config: testConfig(), weather: testWeather()),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('Hourly'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Precip.'), findsOneWidget);
    expect(find.text('NE 5 mph'), findsOneWidget);
  });

  testWidgets('weather panel renders configured location label', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 340,
        height: 520,
        child: WeatherPanel(
          config: testConfig(
            weather: const WeatherConfig(
              enable: true,
              pirateWeatherKey: null,
              forecastLat: null,
              forecastLong: null,
              forecastLanguage: 'en',
              forecastUnits: 'us',
              refreshInterval: 3600,
              locationLabel: 'Farmington',
            ),
          ),
          weather: testWeather(),
        ),
      ),
    );
    expectNoFlutterErrors();
    expect(find.text('Farmington'), findsOneWidget);
  });

  testWidgets('calendar renders a Sunday-first six-week date grid', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 360,
        child: AliceCalendar(
          selectedDate: DateTime(2026, 5, 16),
          onDateSelected: (_) {},
        ),
      ),
    );

    expectNoFlutterErrors();
    expect(find.textContaining('May', findRichText: true), findsOneWidget);

    final calendar = find.byType(AliceCalendar);
    final dayCells = find.descendant(
      of: calendar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('calendar-day-'),
      ),
    );
    final renderedDates = tester
        .widgetList<InkWell>(dayCells)
        .map((cell) => (cell.key! as ValueKey<String>).value.substring(13))
        .toList();
    final expectedDates = List.generate(42, (index) {
      final date = DateTime(2026, 4, 26).add(Duration(days: index));
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    });

    expect(renderedDates, expectedDates);
    expect(renderedDates, hasLength(6 * 7));
    expect(renderedDates.first, '2026-04-26');
    expect(renderedDates.last, '2026-06-06');
  });

  testWidgets('calendar navigation preserves selection and indicators', (
    tester,
  ) async {
    final selected = <DateTime>[];
    final displayedMonths = <DateTime>[];

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 360,
        child: AliceCalendar(
          selectedDate: DateTime(2026, 5, 16),
          indicators: {
            '2026-05-17': [Colors.green, Colors.blue],
          },
          onDateSelected: selected.add,
          onMonthChanged: displayedMonths.add,
        ),
      ),
    );

    Finder day(String key) => find.byKey(ValueKey('calendar-day-$key'));

    final indicatorDots = find.descendant(
      of: day('2026-05-17'),
      matching: find.byWidgetPredicate((widget) {
        if (widget case Container(decoration: final BoxDecoration decoration)) {
          return decoration.shape == BoxShape.circle &&
              decoration.color?.toARGB32() == Colors.green.toARGB32();
        }
        return false;
      }),
    );
    expect(indicatorDots, findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    expect(displayedMonths, [DateTime(2026, 4)]);
    expect(find.textContaining('April', findRichText: true), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    expect(displayedMonths, [DateTime(2026, 4), DateTime(2026, 5)]);
    expect(find.textContaining('May', findRichText: true), findsOneWidget);

    await tester.tap(day('2026-05-17'));
    await tester.pump();
    expect(selected, [DateTime(2026, 5, 17)]);
    expect(indicatorDots, findsOneWidget);
  });

  testWidgets('calendar derives distinct today and selected decorations', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final selected = today.day == daysInMonth
        ? today.subtract(const Duration(days: 1))
        : today.add(const Duration(days: 1));

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 360,
        child: AliceCalendar(selectedDate: selected, onDateSelected: (_) {}),
      ),
    );

    String dateKey(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    BoxDecoration dayDecoration(DateTime date) {
      final cell = find.byKey(ValueKey('calendar-day-${dateKey(date)}'));
      final container = tester
          .widgetList<Container>(
            find.descendant(of: cell, matching: find.byType(Container)),
          )
          .singleWhere((widget) => widget.constraints?.maxWidth == 30);
      return container.decoration! as BoxDecoration;
    }

    final primary = Theme.of(
      tester.element(find.byType(AliceCalendar)),
    ).colorScheme.primary;
    final selectedDecoration = dayDecoration(selected);
    final todayDecoration = dayDecoration(today);

    expect(selectedDecoration.color, primary);
    expect(todayDecoration.color, primary.withValues(alpha: 0.12));
    expect(todayDecoration.color, isNot(selectedDecoration.color));
  });
}
