import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/weather_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily selection uses API date rather than UTC date at rollover', () {
    final now = DateTime.utc(2026, 1, 1, 1);
    WeatherDay entry(DateTime time) => WeatherDay(
      time: time.millisecondsSinceEpoch ~/ 1000,
      summary: '',
      icon: 'clear-day',
    );
    final yesterday = entry(DateTime.utc(2025, 12, 30, 5));
    final today = entry(DateTime.utc(2025, 12, 31, 5));
    final tomorrow = entry(DateTime.utc(2026, 1, 1, 5));
    expect(
      dailyForecastWindow([yesterday, today, tomorrow], now: now, offset: -5),
      [today, tomorrow],
    );
    expect(dailyForecastLabel(today.time.toInt(), -5, now: now), 'Today');
    expect(dailyForecastLabel(tomorrow.time.toInt(), -5, now: now), 'Thu');
  });

  test('plot ranges are padded for empty, constant and lone data', () {
    for (final values in <List<double?>>[
      [],
      [null],
      [12],
      [12, 12],
    ]) {
      final plot = ForecastPlotData([values]);
      expect(plot.minY.isFinite, isTrue);
      expect(plot.maxY, greaterThan(plot.minY));
      expect(plot.hasValues, values.contains(12));
    }
    final plot = ForecastPlotData([
      [null, 12, null, double.nan],
    ]);
    expect(plot.series.single[0].isNull(), isTrue);
    expect(plot.series.single[1].x, 1.5);
    expect(plot.series.single[3].isNull(), isTrue);
    expect(plot.isIsolated(0, 1), isTrue);
  });

  test('daily bands break when either series is missing', () {
    final plot = ForecastPlotData([
      [20, 21, null, 23, 24, 25],
      [10, 11, 12, 13, 14, null],
    ]);
    expect(plot.bands.length, 2);
    expect(plot.bands[0].high.map((spot) => spot.x), [0.5, 1.5]);
    expect(plot.bands[1].low.map((spot) => spot.x), [3.5, 4.5]);
    expect(plot.minY, lessThan(10));
    expect(plot.maxY, greaterThan(25));
  });

  final now = DateTime.utc(2026, 9, 8, 23, 37);
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  WeatherPoint hour(int delta) => WeatherPoint(
    time: seconds + delta * 3600,
    summary: '',
    icon: 'clear-day',
  );
  WeatherDay day(int delta) =>
      WeatherDay(time: seconds + delta * 86400, summary: '', icon: 'clear-day');

  test('hourly starts at closest past sample before applying limit', () {
    final entries = List.generate(60, (i) => hour(i - 30));
    final window = hourlyForecastWindow(entries, now: now);
    expect(window.length, 24);
    expect(window.first, entries[30]);
    expect(hourlyForecastWindow([hour(1), hour(2)], now: now).first, hour(1));
    expect(hourlyForecastWindow([hour(-2), hour(-1)], now: now), [hour(-1)]);
    expect(hourlyForecastWindow([], now: now), isEmpty);
  });

  test('daily starts today, then future, then first stale day', () {
    final entries = List.generate(12, (i) => day(i - 2));
    final window = dailyForecastWindow(entries, now: now, offset: 5.5);
    expect(window.length, 7);
    expect(window.first, day(0));
    expect(dailyForecastWindow([day(-2), day(1)], now: now, offset: 0), [
      day(1),
    ]);
    expect(dailyForecastWindow([day(-2), day(-1)], now: now, offset: 0), [
      day(-2),
      day(-1),
    ]);
    expect(dailyForecastWindow([], now: now, offset: 0), isEmpty);
  });

  test(
    'labels preserve minutes, API day rollover and abbreviated weekdays',
    () {
      expect(hourlyForecastLabel(seconds, 5.5, isNow: false), '05:07');
      expect(hourlyForecastLabel(seconds, 5.5, isNow: true), 'Now');
      expect(dailyForecastLabel(seconds, 5.5, now: now), 'Today');
      expect(dailyForecastLabel(seconds + 86400, 5.5, now: now), 'Thu');
      expect(dailyForecastLabel(seconds - 86400, 5.5, now: now), 'Tue');
    },
  );
}
