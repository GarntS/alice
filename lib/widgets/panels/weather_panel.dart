import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../alice_config.dart';
import '../../alice_theme.dart';
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import '../weather_format.dart';

class WeatherPanel extends StatelessWidget {
  const WeatherPanel({super.key, required this.config, required this.weather});

  final AliceConfig config;
  final WeatherSnapshot? weather;

  @override
  Widget build(BuildContext context) {
    final weather = this.weather;
    if (weather == null) {
      return const Center(
        child: Text('Weather data unavailable.', textAlign: TextAlign.center),
      );
    }

    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CurrentHeader(config: config, weather: weather),
          const SizedBox(height: 8),
          Text(
            weather.currently.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 14),
          _MetricsCard(weather: weather),
          const SizedBox(height: 16),
          Text('Hourly', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _HourlyForecast(config: config, weather: weather),
          const SizedBox(height: 16),
          Text('Daily', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _DailyForecast(config: config, weather: weather),
        ],
      ),
    );
  }
}

class _CurrentHeader extends StatelessWidget {
  const _CurrentHeader({required this.config, required this.weather});

  final AliceConfig config;
  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AliceIcon(weatherIcon(weather.currently.icon), size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (config.weather.locationLabel != null) ...[
                Text(
                  config.weather.locationLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              TemperatureText(
                value: weather.currently.temperature,
                units: weather.units,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.weather});

  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AliceColorTokens.of(context);
    final current = weather.currently;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: colors.raisedContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accentBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetricColumn(
              icon: windDirectionIcon(current.windBearing),
              label: windSpeedLabel(
                current.windSpeed,
                weather.units,
                bearing: current.windBearing,
              ),
            ),
          ),
          Expanded(
            child: _MetricColumn(
              icon: humidityIcon(current.humidity),
              label: percentLabel(current.humidity),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  percentLabel(current.precipProbability),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Precip.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({required this.icon, required this.label});

  final AliceIconDescriptor icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AliceIcon(icon, size: 32),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _HourlyForecast extends StatelessWidget {
  const _HourlyForecast({required this.config, required this.weather});

  final AliceConfig config;
  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final entries = weather.hourly.take(24).toList(growable: false);
    final nowIndex = _nowHourlyIndex(weather, entries);
    return _HorizontalCardList(
      children: [
        for (var i = 0; i < entries.length; i++)
          _WeatherCard(
            label: i == nowIndex
                ? 'Now'
                : DateFormat.j().format(
                    apiZoneDateTime(entries[i].time.toInt(), weather.offset),
                  ),
            icon: weatherIcon(entries[i].icon),
            temperature: degreeLabel(entries[i].temperature),
            highlighted: i == nowIndex,
            accentColor: config.accentColor,
          ),
      ],
    );
  }
}

class _DailyForecast extends StatelessWidget {
  const _DailyForecast({required this.config, required this.weather});

  final AliceConfig config;
  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final today = apiZoneDateTime(
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      weather.offset,
    );
    var todayIndex = weather.daily.indexWhere((day) {
      final date = apiZoneDateTime(day.time.toInt(), weather.offset);
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    });
    if (todayIndex < 0 && weather.daily.isNotEmpty) todayIndex = 0;

    return _HorizontalCardList(
      children: [
        for (var i = 0; i < weather.daily.length; i++)
          _WeatherCard(
            label: i == todayIndex
                ? 'Today'
                : DateFormat.E().format(
                    apiZoneDateTime(
                      weather.daily[i].time.toInt(),
                      weather.offset,
                    ),
                  ),
            icon: weatherIcon(
              weather.daily[i].icon,
              moonPhase: weather.daily[i].moonPhase,
            ),
            temperature: degreeLabel(weather.daily[i].temperatureHigh),
            lowTemperature: degreeLabel(weather.daily[i].temperatureLow),
            highlighted: i == todayIndex,
            accentColor: config.accentColor,
          ),
      ],
    );
  }
}

class _HorizontalCardList extends StatefulWidget {
  const _HorizontalCardList({required this.children});

  final List<Widget> children;

  @override
  State<_HorizontalCardList> createState() => _HorizontalCardListState();
}

class _HorizontalCardListState extends State<_HorizontalCardList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return Text(
        'No forecast data.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return SizedBox(
      height: 124,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && _controller.hasClients) {
            final next = (_controller.offset + event.scrollDelta.dy).clamp(
              0.0,
              _controller.position.maxScrollExtent,
            );
            _controller.jumpTo(next);
          }
        },
        child: ScrollConfiguration(
          behavior: const _WeatherCarouselScrollBehavior(),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: false,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: Row(children: widget.children),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCarouselScrollBehavior extends MaterialScrollBehavior {
  const _WeatherCarouselScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.label,
    required this.icon,
    required this.temperature,
    required this.highlighted,
    required this.accentColor,
    this.lowTemperature,
  });

  final String label;
  final AliceIconDescriptor icon;
  final String temperature;
  final String? lowTemperature;
  final bool highlighted;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AliceColorTokens.of(context);
    final background = highlighted ? accentColor : colors.raisedContainer;
    final foreground = highlighted
        ? (ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
              ? Colors.white
              : Colors.black)
        : theme.colorScheme.onSurface;
    final lowColor = highlighted
        ? foreground.withValues(alpha: 0.72)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: 78,
      height: 112,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodySmall!.copyWith(color: foreground),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
            const SizedBox(height: 8),
            AliceIcon(icon, size: 30, color: foreground),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    temperature,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (lowTemperature != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      lowTemperature!,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(color: lowColor),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

int _nowHourlyIndex(WeatherSnapshot weather, List<WeatherPoint> entries) {
  if (entries.isEmpty) return -1;
  final now = apiZoneDateTime(
    DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    weather.offset,
  ).millisecondsSinceEpoch;
  var selected = -1;
  var selectedTime = -9223372036854775808;
  for (var i = 0; i < entries.length; i++) {
    final time = apiZoneDateTime(
      entries[i].time.toInt(),
      weather.offset,
    ).millisecondsSinceEpoch;
    if (time <= now && time > selectedTime) {
      selected = i;
      selectedTime = time;
    }
  }
  return selected < 0 ? 0 : selected;
}
