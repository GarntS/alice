import 'package:alicebar/widgets/alice_icon.dart';
import 'package:alicebar/widgets/weather_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Pirate Weather conditions to paired Phosphor descriptors', () {
    expect(weatherIcon('clear-day'), AliceIcons.sun);
    expect(weatherIcon('clear-night'), AliceIcons.moon);
    expect(weatherIcon('rain'), AliceIcons.cloudRain);
    expect(weatherIcon('sleet'), AliceIcons.cloudRain);
    expect(weatherIcon('snow'), AliceIcons.cloudSnow);
    expect(weatherIcon('wind'), AliceIcons.wind);
    expect(weatherIcon('fog'), AliceIcons.cloudFog);
    expect(weatherIcon('cloudy'), AliceIcons.cloud);
    expect(weatherIcon('partly-cloudy-day'), AliceIcons.cloudSun);
    expect(weatherIcon('partly-cloudy-night'), AliceIcons.cloudMoon);
  });

  test('varies moon phases and preserves wind bearing direction', () {
    expect(moonPhaseIcon(null), AliceIcons.moon);
    expect(moonPhaseIcon(0.25), AliceIcons.circleHalf);
    expect(moonPhaseIcon(0.5), AliceIcons.circle);
    expect(windDirectionIcon(22.5), AliceIcons.arrowUpRight);
    expect(windDirectionIcon(270), AliceIcons.arrowLeft);
    expect(windDirectionIcon(null), AliceIcons.compass);
  });

  test('uses humidity descriptors for the existing value ranges', () {
    expect(humidityIcon(null), AliceIcons.dropSimple);
    expect(humidityIcon(0.8), AliceIcons.drop);
    expect(humidityIcon(0.5), AliceIcons.dropHalf);
    expect(humidityIcon(0.3), AliceIcons.dropSimple);
    expect(humidityIcon(0.1), AliceIcons.dropSlash);
  });
}
