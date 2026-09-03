import 'package:material_ui/material_ui.dart';

import 'alice_icon.dart';

String degreeLabel(double? value) => value == null ? '-' : '${value.round()}°';

String degreeUnitLabel(double? value, String units) =>
    value == null ? '-' : '${value.round()}°${temperatureUnitLabel(units)}';

class TemperatureText extends StatelessWidget {
  const TemperatureText({
    super.key,
    required this.value,
    required this.units,
    this.style,
    this.unitScale = 0.68,
    this.maxLines = 1,
    this.overflow = TextOverflow.fade,
    this.softWrap = false,
    this.textAlign,
  });

  final double? value;
  final String units;
  final TextStyle? style;
  final double unitScale;
  final int? maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Text(
        '-',
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      );
    }

    final unit = temperatureUnitLabel(units);
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final fontSize = effectiveStyle.fontSize;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${value!.round()}°'),
          if (unit.isNotEmpty)
            TextSpan(
              text: unit,
              style: fontSize == null
                  ? null
                  : TextStyle(fontSize: fontSize * unitScale),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      style: effectiveStyle,
    );
  }
}

String temperatureUnitLabel(String units) {
  return switch (units) {
    'us' => 'F',
    'ca' || 'uk' || 'si' => 'C',
    _ => '',
  };
}

String percentLabel(double? value) =>
    value == null ? '-' : '${(value * 100).round()}%';

String windUnitLabel(String units) {
  return switch (units) {
    'ca' => 'km/h',
    'uk' || 'us' => 'mph',
    'si' => 'm/s',
    _ => units,
  };
}

String windDirectionShortLabel(double? bearing) {
  if (bearing == null) return '';
  final rounded = ((bearing / 45).round() * 45) % 360;
  return switch (rounded) {
    0 => 'N',
    45 => 'NE',
    90 => 'E',
    135 => 'SE',
    180 => 'S',
    225 => 'SW',
    270 => 'W',
    315 => 'NW',
    _ => '',
  };
}

String windSpeedLabel(double? value, String units, {double? bearing}) {
  if (value == null) return '-';
  final direction = windDirectionShortLabel(bearing);
  final prefix = direction.isEmpty ? '' : '$direction ';
  return '$prefix${value.ceil()} ${windUnitLabel(units)}';
}

AliceIconDescriptor weatherIcon(String icon, {double? moonPhase}) =>
    switch (icon) {
      'clear-day' => AliceIcons.sun,
      'clear-night' => moonPhaseIcon(moonPhase),
      'rain' || 'sleet' => AliceIcons.cloudRain,
      'snow' => AliceIcons.cloudSnow,
      'wind' => AliceIcons.wind,
      'fog' => AliceIcons.cloudFog,
      'cloudy' => AliceIcons.cloud,
      'partly-cloudy-day' => AliceIcons.cloudSun,
      'partly-cloudy-night' => AliceIcons.cloudMoon,
      _ => AliceIcons.cloud,
    };

AliceIconDescriptor moonPhaseIcon(double? phase) {
  if (phase == null) return AliceIcons.moon;
  final normalized = phase % 1;
  return switch (normalized) {
    < 0.06 => AliceIcons.circle,
    < 0.25 => AliceIcons.moon,
    < 0.31 => AliceIcons.circleHalf,
    < 0.44 => AliceIcons.moon,
    < 0.56 => AliceIcons.circle,
    < 0.75 => AliceIcons.moon,
    < 0.81 => AliceIcons.circleHalf,
    _ => AliceIcons.moon,
  };
}

AliceIconDescriptor humidityIcon(double? humidity) {
  if (humidity == null) return AliceIcons.dropSimple;
  if (humidity >= 0.75) return AliceIcons.drop;
  if (humidity >= 0.5) return AliceIcons.dropHalf;
  if (humidity >= 0.25) return AliceIcons.dropSimple;
  return AliceIcons.dropSlash;
}

AliceIconDescriptor windDirectionIcon(double? bearing) {
  if (bearing == null) return AliceIcons.compass;
  return switch (((bearing / 45).round() * 45) % 360) {
    0 => AliceIcons.arrowUp,
    45 => AliceIcons.arrowUpRight,
    90 => AliceIcons.arrowRight,
    135 => AliceIcons.arrowDownRight,
    180 => AliceIcons.arrowDown,
    225 => AliceIcons.arrowDownLeft,
    270 => AliceIcons.arrowLeft,
    315 => AliceIcons.arrowUpLeft,
    _ => AliceIcons.compass,
  };
}

DateTime apiZoneDateTime(int seconds, double offsetHours) {
  final millis = (seconds * 1000) + (offsetHours * 3600 * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
