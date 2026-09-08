import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../rust_gen/state.dart';
import 'weather_format.dart';

/// Slot centers are shared by annotation widgets and fl_chart's x coordinates.
double forecastSlotX(int index) => index + 0.5;

class ForecastPlotData {
  ForecastPlotData(List<List<double?>> values)
    : series = [
        for (final row in values)
          [
            for (var i = 0; i < row.length; i++)
              row[i] != null && row[i]!.isFinite
                  ? FlSpot(forecastSlotX(i), row[i]!)
                  : FlSpot.nullSpot,
          ],
      ] {
    final valid = values
        .expand((row) => row)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();
    hasValues = valid.isNotEmpty;
    final low = valid.isEmpty ? 0.0 : valid.reduce(math.min);
    final high = valid.isEmpty ? 0.0 : valid.reduce(math.max);
    final padding = math.max(1.0, (high - low) * 0.15);
    minY = low - padding;
    maxY = high + padding;
  }

  final List<List<FlSpot>> series;
  late final bool hasValues;
  late final double minY;
  late final double maxY;

  /// Contiguous samples for which both daily temperatures are available.
  /// Separate bands avoid connecting across a gap in either line.
  List<({List<FlSpot> high, List<FlSpot> low})> get bands {
    final result = <({List<FlSpot> high, List<FlSpot> low})>[];
    if (series.length < 2) return result;
    var high = <FlSpot>[];
    var low = <FlSpot>[];
    void finish() {
      if (high.length > 1) result.add((high: high, low: low));
      high = [];
      low = [];
    }

    for (var i = 0; i < math.min(series[0].length, series[1].length); i++) {
      if (series[0][i].isNull() || series[1][i].isNull()) {
        finish();
      } else {
        high.add(series[0][i]);
        low.add(series[1][i]);
      }
    }
    finish();
    return result;
  }

  bool isIsolated(int seriesIndex, int index) {
    final spots = series[seriesIndex];
    return !spots[index].isNull() &&
        (index == 0 || spots[index - 1].isNull()) &&
        (index == spots.length - 1 || spots[index + 1].isNull());
  }
}

List<WeatherPoint> hourlyForecastWindow(
  List<WeatherPoint> entries, {
  required DateTime now,
}) {
  if (entries.isEmpty) return const [];
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  var start = 0;
  int? latest;
  for (var i = 0; i < entries.length; i++) {
    final time = entries[i].time.toInt();
    if (time <= seconds && (latest == null || time > latest)) {
      latest = time;
      start = i;
    }
  }
  return entries.skip(start).take(24).toList(growable: false);
}

DateTime forecastLocalDate(int seconds, double offset) {
  final local = apiZoneDateTime(seconds, offset);
  return DateTime.utc(local.year, local.month, local.day);
}

List<WeatherDay> dailyForecastWindow(
  List<WeatherDay> entries, {
  required DateTime now,
  required double offset,
}) {
  final today = forecastLocalDate(now.millisecondsSinceEpoch ~/ 1000, offset);
  var start = entries.indexWhere(
    (entry) => forecastLocalDate(entry.time.toInt(), offset) == today,
  );
  if (start < 0) {
    start = entries.indexWhere(
      (entry) => forecastLocalDate(entry.time.toInt(), offset).isAfter(today),
    );
  }
  return entries.skip(start < 0 ? 0 : start).take(7).toList(growable: false);
}

String hourlyForecastLabel(int seconds, double offset, {required bool isNow}) =>
    isNow
    ? 'Now'
    : DateFormat('HH:mm').format(apiZoneDateTime(seconds, offset));

String dailyForecastLabel(int seconds, double offset, {required DateTime now}) {
  final date = forecastLocalDate(seconds, offset);
  final today = forecastLocalDate(now.millisecondsSinceEpoch ~/ 1000, offset);
  return date == today ? 'Today' : DateFormat.E().format(date);
}
