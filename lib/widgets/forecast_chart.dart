import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'weather_forecast.dart';

Color forecastLowColor(BuildContext context, Color accent) =>
    Color.lerp(accent, Theme.of(context).colorScheme.surface, 0.4)!;

/// Annotations and plot share one coordinate system and one scroll surface.
class ForecastChart extends StatefulWidget {
  const ForecastChart({
    super.key,
    required this.annotations,
    required this.plot,
    required this.accentColor,
    this.footer,
  });

  final List<Widget> annotations;
  final ForecastPlotData plot;
  final Color accentColor;
  final Widget? footer;

  @override
  State<ForecastChart> createState() => _ForecastChartState();
}

class _ForecastChartState extends State<ForecastChart> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.annotations.isEmpty) {
      return Text(
        'No forecast data.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return LayoutBuilder(
      builder: (context, available) {
        final viewportHeight = available.hasBoundedHeight
            ? math.max(
                0.0,
                available.maxHeight - (widget.footer == null ? 0 : 28),
              )
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: viewportHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slotWidth = constraints.maxWidth / 5;
                  return Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent ||
                          !_controller.hasClients)
                        return;
                      final delta = event.scrollDelta.dx != 0
                          ? event.scrollDelta.dx
                          : event.scrollDelta.dy;
                      final next = (_controller.offset + delta).clamp(
                        0.0,
                        _controller.position.maxScrollExtent,
                      );
                      if (next == _controller.offset) return;
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) {
                          _controller.jumpTo(next);
                        },
                      );
                    },
                    child: ScrollConfiguration(
                      behavior: const _ForecastScrollBehavior(),
                      child: Scrollbar(
                        controller: _controller,
                        thumbVisibility: false,
                        child: SingleChildScrollView(
                          controller: _controller,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(
                              slotWidth * widget.annotations.length,
                              constraints.maxWidth,
                            ),
                            height: viewportHeight,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (viewportHeight == null)
                                  _annotations(slotWidth, false)
                                else
                                  Expanded(
                                    flex: 3,
                                    child: _annotations(slotWidth, true),
                                  ),
                                const SizedBox(height: 4),
                                if (viewportHeight == null)
                                  SizedBox(height: 88, child: _plot(context))
                                else
                                  Expanded(flex: 2, child: _plot(context)),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.footer != null)
              SizedBox(
                height: 28,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: widget.footer!,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _annotations(double slotWidth, bool bounded) => Row(
    crossAxisAlignment: bounded
        ? CrossAxisAlignment.stretch
        : CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < widget.annotations.length; i++)
        SizedBox(
          key: ValueKey('forecast-slot-$i'),
          width: slotWidth,
          child: bounded
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: slotWidth,
                    child: widget.annotations[i],
                  ),
                )
              : widget.annotations[i],
        ),
    ],
  );

  Widget _plot(BuildContext context) {
    final plot = widget.plot;
    if (!plot.hasValues) {
      return const Center(
        child: Text(
          'Temperature data unavailable.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      );
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final lowColor = forecastLowColor(context, widget.accentColor);
    final isShortForecast = widget.annotations.length < 5;
    final chartSlots = isShortForecast
        ? 5.0
        : widget.annotations.length.toDouble();
    final series = [
      for (final spots in plot.series)
        isShortForecast ? _extendSpots(spots, chartSlots) : spots,
    ];
    final bars = <LineChartBarData>[
      for (var i = 0; i < series.length; i++)
        LineChartBarData(
          spots: series[i],
          color: i == 0 ? widget.accentColor : lowColor,
          barWidth: 2,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          isCurved: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: series.length == 1 || i == 1,
            color: (i == 1 ? lowColor : widget.accentColor).withValues(
              alpha: 0.12,
            ),
          ),
        ),
    ];
    final bands = <BetweenBarsData>[];
    for (var bandIndex = 0; bandIndex < plot.bands.length; bandIndex++) {
      final band = plot.bands[bandIndex];
      final index = bars.length;
      final bandSeries = isShortForecast && bandIndex == plot.bands.length - 1
          ? [
              _extendSpots(band.high, chartSlots),
              _extendSpots(band.low, chartSlots),
            ]
          : [band.high, band.low];
      for (final spots in bandSeries) {
        bars.add(
          LineChartBarData(
            spots: spots,
            color: Colors.transparent,
            barWidth: 0,
            dotData: const FlDotData(show: false),
          ),
        );
      }
      bands.add(
        BetweenBarsData(
          fromIndex: index,
          toIndex: index + 1,
          color: widget.accentColor.withValues(alpha: 0.12),
        ),
      );
    }
    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: chartSlots,
        minY: plot.minY,
        maxY: plot.maxY,
        lineBarsData: bars,
        betweenBarsData: bands,
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        extraLinesData: ExtraLinesData(
          extraLinesOnTop: false,
          verticalLines: [
            for (var i = 0; i < widget.annotations.length; i++)
              VerticalLine(
                x: forecastSlotX(i),
                color: muted.withValues(alpha: 0.2),
                strokeWidth: 1,
              ),
          ],
        ),
      ),
      duration: Duration.zero,
    );
    return KeyedSubtree(key: const ValueKey('forecast-plot'), child: chart);
  }
}

List<FlSpot> _extendSpots(List<FlSpot> spots, double targetX) {
  final valid = spots.where((spot) => spot.isNotNull()).toList();
  if (valid.isEmpty || valid.last.x >= targetX) return spots;

  final last = valid.last;
  final previous = valid.length > 1 ? valid[valid.length - 2] : null;
  final slope = previous == null
      ? 0.0
      : (last.y - previous.y) / (last.x - previous.x);
  return [...spots, FlSpot(targetX, last.y + slope * (targetX - last.x))];
}

class _ForecastScrollBehavior extends MaterialScrollBehavior {
  const _ForecastScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}
