import 'package:flutter/material.dart';

import 'metric_pill.dart';

class TopBarMemoryModule extends StatelessWidget {
  const TopBarMemoryModule({super.key, required this.memoryUsagePercent});

  final double memoryUsagePercent;

  @override
  Widget build(BuildContext context) {
    return TopBarMetricPill(
      icon: Icons.memory_rounded,
      label: '${memoryUsagePercent.toStringAsFixed(0)}%',
      alert: memoryUsagePercent >= 90,
      warning: memoryUsagePercent >= 75,
    );
  }
}
