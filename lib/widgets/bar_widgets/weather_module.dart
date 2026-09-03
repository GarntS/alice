import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import '../../panel_controller.dart';
import '../../rust_gen/state.dart';
import '../weather_format.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarWeatherModule extends StatelessWidget {
  const TopBarWeatherModule({
    super.key,
    required this.weather,
    required this.highlighted,
    required this.onToggle,
  });

  final WeatherSnapshot? weather;
  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    final current = weather?.currently;
    return TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: current == null ? AliceIcons.cloud : weatherIcon(current.icon),
        label: current == null ? '-' : '',
        labelWidget: current == null
            ? null
            : TemperatureText(
                value: current.temperature,
                units: weather!.units,
                overflow: TextOverflow.ellipsis,
              ),
        highlighted: highlighted,
      ),
    );
  }
}
