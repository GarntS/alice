import 'package:alicebar/widgets/forecast_chart.dart';
import 'package:alicebar/widgets/weather_forecast.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  for (final values in <List<double?>>[
    [],
    [null],
    [12],
    [12, 12],
    [12, null, 14],
  ]) {
    testWidgets('renders sparse forecast $values without invented points', (
      tester,
    ) async {
      final plot = ForecastPlotData([values, values]);
      await pumpAliceWidget(
        tester,
        SizedBox(
          width: 320,
          child: ForecastChart(
            annotations: [
              for (final value in values) Text(value == null ? '-' : '$value°'),
            ],
            plot: plot,
            accentColor: Colors.blue,
          ),
        ),
      );
      expectNoFlutterErrors();
      if (values.isEmpty) {
        expect(find.text('No forecast data.'), findsOneWidget);
        expect(find.byType(LineChart), findsNothing);
      } else if (!plot.hasValues) {
        expect(find.text('-'), findsOneWidget);
        expect(find.text('Temperature data unavailable.'), findsOneWidget);
        expect(find.byType(LineChart), findsNothing);
      } else {
        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        expect(
          data.lineBarsData.first.spots.length,
          greaterThanOrEqualTo(values.length),
        );
        for (var i = 0; i < values.length; i++) {
          final bar = data.lineBarsData.first;
          final spot = bar.spots[i];
          expect(spot.isNull(), values[i] == null);
          if (values[i] != null && plot.isIsolated(0, i)) {
            expect(bar.dotData.checkToShowDot(spot, bar), isTrue);
          }
        }
        if (values.contains(null)) expect(data.betweenBarsData, isEmpty);
      }
    });
  }

  testWidgets(
    'daily series have a faint band, hidden axes and no touch feedback',
    (tester) async {
      await pumpAliceWidget(
        tester,
        SizedBox(
          width: 320,
          child: ForecastChart(
            annotations: const [Text('Today'), Text('Thu'), Text('Fri')],
            plot: ForecastPlotData([
              [20, 21, 22],
              [10, 11, 12],
            ]),
            accentColor: Colors.blue,
          ),
        ),
      );
      final finder = find.byType(LineChart);
      final data = tester.widget<LineChart>(finder).data;
      expect(data.lineBarsData[0].color, Colors.blue);
      expect(
        data.lineBarsData[1].color,
        forecastLowColor(tester.element(finder), Colors.blue),
      );
      expect(data.lineBarsData[1].belowBarData.show, isTrue);
      expect(
        data.lineBarsData[1].belowBarData.color,
        data.lineBarsData[1].color!.withValues(alpha: 0.12),
      );
      expect(data.lineBarsData[0].spots, hasLength(4));
      expect(data.lineBarsData[1].spots, hasLength(4));
      expect(data.lineBarsData[0].spots.last.x, 5);
      expect(data.lineBarsData[1].spots.last.x, 5);
      expect(data.betweenBarsData, hasLength(1));
      expect(data.betweenBarsData.single.color!.a, lessThan(0.15));
      expect(data.titlesData.show, false);
      expect(data.lineTouchData.enabled, false);
      expect(data.extraLinesData.verticalLines.map((line) => line.x), [
        0.5,
        1.5,
        2.5,
      ]);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final surface = find.byKey(const ValueKey('forecast-plot'));
      await mouse.addPointer(location: tester.getCenter(surface));
      await mouse.moveTo(tester.getCenter(surface));
      await tester.tap(surface);
      await tester.pumpAndSettle();
      expect(
        tester.widget<LineChart>(finder).data.showingTooltipIndicators,
        isEmpty,
      );
      await mouse.removePointer();
      expectNoFlutterErrors();
    },
  );

  testWidgets(
    'charts align slots and scroll independently with wheel and drag',
    (tester) async {
      Widget chart(String key) => ForecastChart(
        key: ValueKey(key),
        annotations: List.generate(
          24,
          (i) => Text('slot $i', textAlign: TextAlign.center),
        ),
        plot: ForecastPlotData([List.generate(24, (i) => i.toDouble())]),
        accentColor: Colors.blue,
      );
      await pumpAliceWidget(
        tester,
        SizedBox(
          width: 320,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              children: [
                chart('hourly'),
                chart('daily'),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      final hourly = find.byKey(const ValueKey('hourly'));
      final daily = find.byKey(const ValueKey('daily'));
      Finder scroller(Finder chart) => find.descendant(
        of: chart,
        matching: find.byType(SingleChildScrollView),
      );
      final h = tester
          .widget<SingleChildScrollView>(scroller(hourly))
          .controller!;
      final d = tester
          .widget<SingleChildScrollView>(scroller(daily))
          .controller!;
      void checkAlignment() {
        final plot = find.descendant(
          of: hourly,
          matching: find.byKey(const ValueKey('forecast-plot')),
        );
        final rect = tester.getRect(plot);
        final slot = find.descendant(
          of: hourly,
          matching: find.byKey(const ValueKey('forecast-slot-3')),
        );
        expect(
          tester.getCenter(slot).dx,
          closeTo(rect.left + rect.width * 3.5 / 24, 0.01),
        );
      }

      expect(
        tester
            .getSize(
              find.descendant(
                of: hourly,
                matching: find.byKey(const ValueKey('forecast-slot-0')),
              ),
            )
            .width,
        64,
      );
      checkAlignment();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(hourly),
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.offset, 100);
      expect(d.offset, 0);
      checkAlignment();
      await tester.drag(hourly, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(h.offset, greaterThan(100));
      expect(d.offset, 0);
      final scrolledPlot = find.descendant(
        of: hourly,
        matching: find.byKey(const ValueKey('forecast-plot')),
      );
      expect(scrolledPlot, findsOneWidget);
      expect(
        tester
            .widget<LineChart>(
              find.descendant(
                of: scrolledPlot,
                matching: find.byType(LineChart),
              ),
            )
            .data
            .lineBarsData
            .single
            .spots,
        hasLength(24),
      );
      checkAlignment();
      await tester.drag(
        daily,
        const Offset(-80, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(d.offset, greaterThan(0));
      final outer = find.byType(SingleChildScrollView).first;
      await tester.drag(hourly, const Offset(0, -100));
      await tester.pumpAndSettle();
      final outerScrollable = find
          .descendant(of: outer, matching: find.byType(Scrollable))
          .first;
      expect(
        tester.state<ScrollableState>(outerScrollable).position.pixels,
        greaterThan(0),
      );
      for (final scrollbar in tester.widgetList<Scrollbar>(
        find.byType(Scrollbar),
      )) {
        expect(scrollbar.thumbVisibility, false);
      }
      expectNoFlutterErrors();
    },
  );
}
