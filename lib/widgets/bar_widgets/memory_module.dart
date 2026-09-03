import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import 'metric_pill.dart';

class TopBarMemoryModule extends StatelessWidget {
  const TopBarMemoryModule({super.key, required this.memoryUsagePercent});

  final double memoryUsagePercent;

  @override
  Widget build(BuildContext context) {
    return TopBarMetricPill(
      icon: AliceIcons.memory,
      label: '${memoryUsagePercent.toStringAsFixed(0)}%',
      alert: memoryUsagePercent >= 90,
      warning: memoryUsagePercent >= 75,
    );
  }
}
