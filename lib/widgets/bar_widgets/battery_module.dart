import 'package:material_ui/material_ui.dart';

import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import 'metric_pill.dart';

AliceIconDescriptor batteryIconFor(BatterySnapshot battery) {
  if (battery.status == 'Charging' || battery.status == 'Full') {
    return AliceIcons.batteryCharging;
  }
  return switch (battery.capacity) {
    <= 10 => AliceIcons.batteryWarning,
    <= 33 => AliceIcons.batteryLow,
    <= 55 => AliceIcons.batteryMedium,
    <= 77 => AliceIcons.batteryHigh,
    _ => AliceIcons.batteryFull,
  };
}

class TopBarBatteryModule extends StatelessWidget {
  const TopBarBatteryModule({super.key, required this.battery});

  final BatterySnapshot? battery;

  @override
  Widget build(BuildContext context) {
    if (battery == null) return const SizedBox.shrink();
    return TopBarMetricPill(
      icon: batteryIconFor(battery!),
      label: '${battery!.capacity}%',
      warning: battery!.capacity <= 33,
      alert: battery!.capacity <= 10,
    );
  }
}
