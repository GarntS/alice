import 'package:flutter/material.dart';

import '../../panel_controller.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarNotificationModule extends StatelessWidget {
  const TopBarNotificationModule({
    super.key,
    required this.highlighted,
    required this.unreadCount,
    required this.onToggle,
  });

  final bool highlighted;
  final int unreadCount;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TopBarPill(
            icon: Icons.notifications_rounded,
            label: '',
            highlighted: highlighted,
          ),
          if (unreadCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
