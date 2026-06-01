import 'package:flutter/material.dart';

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

IconData weatherIcon(String icon, {double? moonPhase}) {
  return switch (icon) {
    'clear-day' => Icons.wb_sunny_rounded,
    'clear-night' => moonPhaseIcon(moonPhase),
    'rain' => Icons.water_drop_rounded,
    'snow' => Icons.ac_unit_rounded,
    'sleet' => Icons.grain_rounded,
    'wind' => Icons.air_rounded,
    'fog' => Icons.foggy,
    'cloudy' => Icons.cloud_rounded,
    'partly-cloudy-day' => Icons.wb_cloudy_rounded,
    'partly-cloudy-night' => Icons.nights_stay_rounded,
    _ => Icons.cloud_rounded,
  };
}

IconData moonPhaseIcon(double? phase) {
  if (phase == null) return Icons.nightlight_round;
  if (phase < 0.06 || phase >= 0.94)
    return Icons.radio_button_unchecked_rounded;
  if (phase < 0.25) return Icons.brightness_2_rounded;
  if (phase < 0.31) return Icons.contrast_rounded;
  if (phase < 0.44) return Icons.brightness_3_rounded;
  if (phase < 0.56) return Icons.circle_rounded;
  if (phase < 0.75) return Icons.brightness_3_rounded;
  if (phase < 0.81) return Icons.contrast_rounded;
  return Icons.brightness_2_rounded;
}

IconData humidityIcon(double? humidity) {
  if (humidity == null) return Icons.water_drop_outlined;
  if (humidity >= 0.75) return Icons.water_drop_rounded;
  if (humidity >= 0.5) return Icons.opacity_rounded;
  if (humidity >= 0.25) return Icons.opacity_outlined;
  return Icons.dry_rounded;
}

IconData windDirectionIcon(double? bearing) {
  if (bearing == null) return Icons.explore_rounded;
  final rounded = ((bearing / 45).round() * 45) % 360;
  return switch (rounded) {
    0 => Icons.north_rounded,
    45 => Icons.north_east_rounded,
    90 => Icons.east_rounded,
    135 => Icons.south_east_rounded,
    180 => Icons.south_rounded,
    225 => Icons.south_west_rounded,
    270 => Icons.west_rounded,
    315 => Icons.north_west_rounded,
    _ => Icons.explore_rounded,
  };
}

DateTime apiZoneDateTime(int seconds, double offsetHours) {
  final millis = (seconds * 1000) + (offsetHours * 3600 * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
