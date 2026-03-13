import 'package:flutter/material.dart';

import '../../../data/bar_snapshot.dart';
import 'pill.dart';

class TopBarNetworkModule extends StatelessWidget {
  const TopBarNetworkModule({
    super.key,
    required this.networkKind,
    required this.label,
  });

  final NetworkKind networkKind;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TopBarPill(
      icon: switch (networkKind) {
        NetworkKind.wifi => Icons.wifi_rounded,
        NetworkKind.wired => Icons.settings_ethernet_rounded,
        NetworkKind.disconnected => Icons.portable_wifi_off_rounded,
      },
      label: label,
    );
  }
}
