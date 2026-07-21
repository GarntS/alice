import 'dart:async';

import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/panels/clock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets('an older date completion cannot replace active event state', (
    tester,
  ) async {
    final fetcher = _ControlledCalendarFetcher();
    await _pumpClockPanel(tester, fetcher);

    final dateA = fetcher.requests.single;
    final selectedA = DateTime.parse(dateA);
    final selectedB = selectedA.add(const Duration(days: 1));
    final dateB = _dateKey(selectedB);

    await tester.tap(find.byKey(ValueKey('calendar-day-$dateB')));
    await tester.pump();
    expect(fetcher.requests, [dateA, dateB]);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    fetcher.completeNext(dateB, _ready('Date B', '#00AA00'));
    await tester.pump();
    expect(find.text('Date B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    final requestCount = fetcher.requests.length;
    fetcher.completeNext(dateA, _needsAuth());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Date B'), findsOneWidget);
    expect(find.text('Connect Google Calendar'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(fetcher.requests, hasLength(requestCount));
  });

  testWidgets('polling reads the selected date and stops after ready', (
    tester,
  ) async {
    final fetcher = _ControlledCalendarFetcher();
    await _pumpClockPanel(tester, fetcher);

    final dateA = fetcher.requests.single;
    fetcher.completeNext(dateA, _needsAuth());
    await tester.pump();

    final selectedB = DateTime.parse(dateA).add(const Duration(days: 1));
    final dateB = _dateKey(selectedB);
    await tester.tap(find.byKey(ValueKey('calendar-day-$dateB')));
    await tester.pump();
    fetcher.completeNext(dateB, _needsAuth());
    await tester.pump();

    await tester.pump(const Duration(seconds: 5));
    expect(fetcher.requests.where((date) => date == dateB), hasLength(2));
    expect(fetcher.requests.where((date) => date == dateA), hasLength(1));

    fetcher.completeNext(dateB, _ready('Authorized'));
    await tester.pump();
    final requestCountAfterReady = fetcher.requests.length;

    await tester.pump(const Duration(seconds: 10));
    expect(fetcher.requests, hasLength(requestCountAfterReady));
    expect(find.text('Authorized'), findsOneWidget);
  });

  testWidgets('an older month completion cannot replace current indicators', (
    tester,
  ) async {
    final fetcher = _ControlledCalendarFetcher();
    await _pumpClockPanel(tester, fetcher);

    fetcher.completeNext(fetcher.requests.single, _notConfigured());
    await tester.pump();

    final now = DateTime.now();
    final olderMonth = DateTime(now.year, now.month + 1);
    final currentMonth = DateTime(now.year, now.month + 2);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();

    final currentIndicatorDate = DateTime(
      currentMonth.year,
      currentMonth.month,
      1,
    );
    fetcher.completeMonth(
      currentMonth,
      resultForDate: (date) => _sameDate(date, currentIndicatorDate)
          ? _ready('Current month', '#00AA00')
          : _ready(),
    );
    await tester.pump();

    expect(
      _dotWithColor(tester, currentIndicatorDate, const Color(0xFF00AA00)),
      findsOneWidget,
    );

    fetcher.completeMonth(
      olderMonth,
      resultForDate: (_) => _ready('Older month', '#AA0000'),
    );
    await tester.pump();

    expect(
      _dotWithColor(tester, currentIndicatorDate, const Color(0xFF00AA00)),
      findsOneWidget,
    );
    expect(
      _dotWithColor(tester, currentIndicatorDate, const Color(0xFFAA0000)),
      findsNothing,
    );
  });

  testWidgets('dispose ignores pending work and cancels polling', (
    tester,
  ) async {
    final fetcher = _ControlledCalendarFetcher();
    await _pumpClockPanel(tester, fetcher);

    final dateA = fetcher.requests.single;
    fetcher.completeNext(dateA, _needsAuth());
    await tester.pump();

    final dateB = _dateKey(DateTime.parse(dateA).add(const Duration(days: 1)));
    await tester.tap(find.byKey(ValueKey('calendar-day-$dateB')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    final requestCount = fetcher.requests.length;
    fetcher.completeNext(dateB, _ready('Too late'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(tester.takeException(), isNull);
    expect(fetcher.requests, hasLength(requestCount));
  });
}

Future<void> _pumpClockPanel(
  WidgetTester tester,
  _ControlledCalendarFetcher fetcher,
) {
  return pumpAliceWidget(
    tester,
    SizedBox(
      width: 400,
      height: 760,
      child: ClockPanel(
        config: testConfig(),
        snapshot: testSnapshot().clock,
        calendarEventFetcher: fetcher.call,
      ),
    ),
  );
}

Finder _dotWithColor(WidgetTester tester, DateTime date, Color color) {
  return find.descendant(
    of: find.byKey(ValueKey('calendar-day-${_dateKey(date)}')),
    matching: find.byWidgetPredicate((widget) {
      if (widget case Container(decoration: final BoxDecoration decoration)) {
        return decoration.shape == BoxShape.circle &&
            decoration.color?.toARGB32() == color.toARGB32();
      }
      return false;
    }),
  );
}

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

CalendarEvent _event(String title, String color) => CalendarEvent(
  id: title,
  title: title,
  isAllDay: true,
  startLabel: '',
  endLabel: '',
  calendarName: 'Test',
  calendarColor: color,
);

CalendarFetchResult _ready([String? title, String color = '#123456']) =>
    CalendarFetchResult(
      status: 'ready',
      events: title == null ? const [] : [_event(title, color)],
    );

CalendarFetchResult _needsAuth() => const CalendarFetchResult(
  status: 'needs_auth',
  events: [],
  authUrl: 'https://example.test/auth',
  authCode: 'ALICE',
);

CalendarFetchResult _notConfigured() =>
    const CalendarFetchResult(status: 'not_configured', events: []);

class _ControlledCalendarFetcher {
  final requests = <String>[];
  final _pending = <String, List<Completer<CalendarFetchResult>>>{};

  Future<CalendarFetchResult> call({required String date}) {
    requests.add(date);
    final completer = Completer<CalendarFetchResult>();
    _pending.putIfAbsent(date, () => []).add(completer);
    return completer.future;
  }

  void completeNext(String date, CalendarFetchResult result) {
    final pending = _pending[date];
    if (pending == null || pending.isEmpty) {
      fail('No pending calendar request for $date');
    }
    pending.removeAt(0).complete(result);
  }

  void completeMonth(
    DateTime month, {
    required CalendarFetchResult Function(DateTime date) resultForDate,
  }) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    for (var day = 1; day <= days; day++) {
      final date = DateTime(month.year, month.month, day);
      completeNext(_dateKey(date), resultForDate(date));
    }
  }
}
