import 'package:material_ui/material_ui.dart';

import '../../alice_config.dart';
import '../../alice_theme.dart';
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import '../weather_format.dart';
import '../weather_forecast.dart';
import '../forecast_chart.dart';

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
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CurrentHeader(config: config, weather: weather),
          const SizedBox(height: 14),
          _MetricsCard(weather: weather),
          const SizedBox(height: 16),
          Text(
            'Hourly',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _HourlyForecast(config: config, weather: weather),
          ),
          const SizedBox(height: 16),
          Text(
            'Daily',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _DailyForecast(config: config, weather: weather),
          ),
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: TemperatureText(
            value: weather.currently.temperature,
            units: weather.units,
            unitScale: 0.45,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weather.currently.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                currentWeatherMetadata(
                  observationSeconds: weather.currently.time.toInt(),
                  offsetHours: weather.offset,
                  locationLabel: config.weather.locationLabel,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AliceIcon(weatherIcon(weather.currently.icon), size: 64),
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
    final entries = hourlyForecastWindow(weather.hourly, now: DateTime.now());
    return ForecastChart(
      key: const ValueKey('hourly-chart'),
      accentColor: config.accentColor,
      plot: ForecastPlotData([
        entries.map((entry) => entry.temperature).toList(),
      ]),
      annotations: [
        for (var i = 0; i < entries.length; i++)
          _ForecastAnnotation(
            label: hourlyForecastLabel(
              entries[i].time.toInt(),
              weather.offset,
              isNow: i == 0,
            ),
            icon: weatherIcon(entries[i].icon),
            temperature: degreeLabel(entries[i].temperature),
          ),
      ],
    );
  }
}

class _ForecastAnnotation extends StatelessWidget {
  const _ForecastAnnotation({
    required this.label,
    required this.icon,
    required this.temperature,
    this.lowTemperature,
  });

  final String label;
  final AliceIconDescriptor icon;
  final String temperature;
  final String? lowTemperature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTextStyle(
      style: theme.textTheme.bodySmall!,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          AliceIcon(icon, size: 30),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  temperature,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (lowTemperature != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    lowTemperature!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: forecastLowColor(
                        context,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyForecast extends StatelessWidget {
  const _DailyForecast({required this.config, required this.weather});

  final AliceConfig config;
  final WeatherSnapshot weather;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final entries = dailyForecastWindow(
      weather.daily,
      now: now,
      offset: weather.offset,
    );
    return ForecastChart(
      key: const ValueKey('daily-chart'),
      footer: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _LegendItem(label: 'High', color: config.accentColor),
          _LegendItem(
            label: 'Low',
            color: forecastLowColor(context, config.accentColor),
          ),
        ],
      ),
      accentColor: config.accentColor,
      plot: ForecastPlotData([
        entries.map((entry) => entry.temperatureHigh).toList(),
        entries.map((entry) => entry.temperatureLow).toList(),
      ]),
      annotations: [
        for (final entry in entries)
          _ForecastAnnotation(
            label: dailyForecastLabel(
              entry.time.toInt(),
              weather.offset,
              now: now,
            ),
            icon: weatherIcon(entry.icon, moonPhase: entry.moonPhase),
            temperature: degreeLabel(entry.temperatureHigh),
            lowTemperature: degreeLabel(entry.temperatureLow),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 2, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    ],
  );
}
