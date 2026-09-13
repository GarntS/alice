import 'package:material_ui/material_ui.dart';

import '../../panel_controller.dart';
import '../bluetooth_icons.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarBluetoothModule extends StatelessWidget {
  const TopBarBluetoothModule({
    super.key,
    required this.onToggle,
    this.highlighted = false,
  });

  final ValueChanged<PanelAnchor> onToggle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Bluetooth',
    button: true,
    child: TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: BluetoothIcons.bluetooth,
        label: '',
        highlighted: highlighted,
      ),
    ),
  );
}
