import 'package:flutter/material.dart';

import 'metric_pill.dart';

class TopBarCpuModule extends StatelessWidget {
  const TopBarCpuModule({super.key, required this.cpuUsageCores});

  final double cpuUsageCores;

  @override
  Widget build(BuildContext context) {
    return TopBarMetricPill(
      icon: Icons.developer_board_rounded,
      label: cpuUsageCores.toStringAsFixed(1),
      alert: cpuUsageCores >= 3.2,
      warning: cpuUsageCores >= 2.4,
    );
  }
}
