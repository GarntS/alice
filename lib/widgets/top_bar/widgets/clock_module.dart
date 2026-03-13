import 'package:flutter/material.dart';

import '../../../data/bar_snapshot.dart';
import '../../../state/panel_controller.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarClockModule extends StatelessWidget {
  const TopBarClockModule({
    super.key,
    required this.localTimeZoneLabel,
    required this.clock,
    required this.highlighted,
    required this.onToggle,
  });

  final String localTimeZoneLabel;
  final ClockSnapshot clock;
  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    return TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: Icons.schedule_rounded,
        label: '$localTimeZoneLabel ${clock.dateLabel} ${clock.timeLabel}',
        highlighted: highlighted,
      ),
    );
  }
}
