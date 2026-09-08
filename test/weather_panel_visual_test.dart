import 'dart:io';
import 'dart:ui' as ui;

import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/panels/weather_panel.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

// Optional review images: flutter test test/weather_panel_visual_test.dart
// --dart-define=WEATHER_REVIEW_DIR=/tmp/alice-weather-review
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final text = FontLoader('NimbusSansDOT')
      ..addFont(rootBundle.load('fonts/NimbusSans-Regular.ttf'));
    await text.load();
    for (final variant in ['', '-Duotone']) {
      final font = FontLoader('packages/phosphoricons_flutter/Phosphor$variant')
        ..addFont(
          rootBundle.load(
            'packages/phosphoricons_flutter/lib/fonts/Phosphor$variant.ttf',
          ),
        );
      await font.load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('weather review ${brightness.name} ${scale}x', (
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
            24,
            (i) => WeatherPoint(
              time: now + i * 3600,
              summary: '',
              icon: i.isEven ? 'clear-day' : 'partly-cloudy-day',
              temperature: [50.0, 54.0, 51.0, 49.0, 53.0][i % 5],
            ),
          ),
          daily: List.generate(
            7,
            (i) => WeatherDay(
              time: now + i * 86400,
              summary: '',
              icon: 'partly-cloudy-day',
              temperatureHigh: [58.0, 62.0, 55.0, 59.0, 61.0][i % 5],
              temperatureLow: [42.0, 46.0, 43.0, 45.0, 47.0][i % 5],
            ),
          ),
          alerts: const [],
        );
        await pumpAliceWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('review'),
            child: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 320,
                    height: 900,
                    child: WeatherPanel(config: testConfig(), weather: weather),
                  ),
                ),
              ),
            ),
          ),
          brightness: brightness,
          size: const Size(400, 960),
        );
        await tester.pumpAndSettle();
        expectNoFlutterErrors();
        const directory = String.fromEnvironment('WEATHER_REVIEW_DIR');
        if (directory.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('review')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/${brightness.name}-${scale}x.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
