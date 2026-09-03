import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import '../../panel_controller.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarPowerModule extends StatelessWidget {
  const TopBarPowerModule({
    super.key,
    required this.highlighted,
    required this.onToggle,
  });

  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    return TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: AliceIcons.power,
        label: '',
        highlighted: highlighted,
      ),
    );
  }
}
