import 'package:alicebar/alice_config.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:alicebar/widgets/panels/weather_panel.dart';
import 'package:alicebar/widgets/weather_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'panel fits actual padded host without outer scrolling at $scale',
      (tester) async {
        await pumpAliceWidget(
          tester,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: 320,
              height: 600,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: WeatherPanel(
                  config: testConfig(),
                  weather: testWeather(),
                ),
              ),
            ),
          ),
        );
        final panel = tester.getRect(find.byType(WeatherPanel));
        final fit = tester.getRect(find.byKey(const ValueKey('daily-chart')));
        expect(fit.width, panel.width);
        expect(fit.left, greaterThanOrEqualTo(panel.left));
        expect(fit.right, lessThanOrEqualTo(panel.right));
        expect(fit.bottom, lessThanOrEqualTo(panel.bottom));
        for (final scroll in tester.widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        )) {
          expect(scroll.scrollDirection, Axis.horizontal);
        }
        expect(
          tester
              .widget<TemperatureText>(find.byType(TemperatureText))
              .unitScale,
          0.45,
        );
        expectNoFlutterErrors();
      },
    );
  }

  testWidgets('panel supplies hourly fill and daily high/low band', (
    tester,
  ) async {
    final base = testWeather();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final weather = WeatherSnapshot(
      latitude: base.latitude,
      longitude: base.longitude,
      timezone: base.timezone,
      offset: base.offset,
      units: base.units,
      lastUpdatedUnixSecs: now,
      currently: base.currently,
      hourly: List.generate(
        30,
        (i) => WeatherPoint(
          time: now + i * 3600,
          summary: '',
          icon: 'clear-day',
          temperature: 20 + i.toDouble(),
        ),
      ),
      daily: List.generate(
        10,
        (i) => WeatherDay(
          time: now + i * 86400,
          summary: '',
          icon: 'clear-night',
          moonPhase: 0.25,
          temperatureHigh: 25 + i.toDouble(),
          temperatureLow: 15 + i.toDouble(),
        ),
      ),
      alerts: const [],
    );
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 800,
        child: WeatherPanel(config: testConfig(), weather: weather),
      ),
    );
    LineChartData data(String key) => tester
        .widget<LineChart>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(LineChart),
          ),
        )
        .data;
    final hourly = data('hourly-chart');
    expect(hourly.lineBarsData, hasLength(1));
    expect(hourly.lineBarsData.single.spots, hasLength(24));
    expect(hourly.lineBarsData.single.belowBarData.show, isTrue);
    final daily = data('daily-chart');
    expect(daily.lineBarsData[0].spots, hasLength(7));
    expect(daily.lineBarsData[0].spots.first.y, 25);
    expect(daily.lineBarsData[1].spots.first.y, 15);
    expect(daily.betweenBarsData, hasLength(1));
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AliceIcon && widget.icon == AliceIcons.circleHalf,
      ),
      findsNWidgets(7),
    );
    expectNoFlutterErrors();
  });

  testWidgets('absent location displays only current observation metadata', (
    tester,
  ) async {
    final weather = testWeather();
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 320,
        height: 600,
        child: WeatherPanel(config: testConfig(), weather: weather),
      ),
    );
    expect(
      find.text(
        currentWeatherMetadata(
          observationSeconds: weather.currently.time.toInt(),
          offsetHours: weather.offset,
        ),
      ),
      findsOneWidget,
    );
    expectNoFlutterErrors();
  });

  testWidgets('Daily heading is plain and chart key fits enlarged text', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SizedBox(
          width: 320,
          height: 800,
          child: WeatherPanel(config: testConfig(), weather: testWeather()),
        ),
      ),
    );
    final chart = find.byKey(const ValueKey('daily-chart'));
    for (final label in ['High', 'Low']) {
      final key = find.text(label);
      expect(find.descendant(of: chart, matching: key), findsOneWidget);
      expect(
        tester.getTopLeft(key).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(
                find.descendant(
                  of: chart,
                  matching: find.byKey(const ValueKey('forecast-plot')),
                ),
              )
              .dy,
        ),
      );
    }
    expect(
      find.descendant(of: chart, matching: find.text('Daily')),
      findsNothing,
    );
    expectNoFlutterErrors();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('header and metrics fit 320px at text scale $scale', (
      tester,
    ) async {
      final base = testWeather();
      const summary =
          'Very long weather summary with considerable detail and more words';
      final weather = WeatherSnapshot(
        latitude: base.latitude,
        longitude: base.longitude,
        timezone: base.timezone,
        offset: -5,
        units: base.units,
        lastUpdatedUnixSecs: 1900000000,
        currently: WeatherPoint(
          time: DateTime.utc(2020, 1, 2, 23, 37).millisecondsSinceEpoch ~/ 1000,
          summary: summary,
          icon: 'clear-day',
          temperature: 50.25,
          humidity: 0.72,
          precipProbability: 0.32,
          windSpeed: 4.52,
          windBearing: 48,
        ),
        hourly: const [],
        daily: const [],
        alerts: const [],
      );
      final config = testConfig(
        weather: const WeatherConfig(
          enable: true,
          pirateWeatherKey: null,
          forecastLat: null,
          forecastLong: null,
          forecastLanguage: 'en',
          forecastUnits: 'us',
          refreshInterval: 3600,
          locationLabel: 'A very long city name that must be truncated',
        ),
      );
      await pumpAliceWidget(
        tester,
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(
            width: 320,
            height: 600,
            child: WeatherPanel(config: config, weather: weather),
          ),
        ),
      );
      expectNoFlutterErrors();
      final temperature = find.byType(TemperatureText);
      final summaryFinder = find.text(summary);
      final metadata = find.text(
        'A very long city name that must be truncated, Current 18:37',
      );
      final icon = find.byWidgetPredicate(
        (widget) => widget is AliceIcon && widget.size == 64,
      );
      expect(summaryFinder, findsOneWidget);
      expect(
        tester.getRect(temperature).right,
        lessThan(tester.getRect(summaryFinder).left),
      );
      expect(
        tester.getRect(summaryFinder).right,
        lessThan(tester.getRect(icon).left),
      );
      final tempStyle = tester.widget<TemperatureText>(temperature).style!;
      final summaryText = tester.widget<Text>(summaryFinder);
      final metadataText = tester.widget<Text>(metadata);
      expect(tempStyle.fontSize, greaterThan(summaryText.style!.fontSize!));
      expect(
        summaryText.style!.fontSize,
        greaterThan(metadataText.style!.fontSize!),
      );
      expect(summaryText.maxLines, 2);
      expect(metadataText.overflow, TextOverflow.ellipsis);
      expect(find.text('NE 5 mph'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('32%'), findsOneWidget);
      expect(find.text('Precip.'), findsOneWidget);
      expect(find.text('No forecast data.'), findsNWidgets(2));
    });
  }
}
