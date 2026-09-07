import 'package:material_ui/material_ui.dart';

import '../../panel_controller.dart';
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarNetworkModule extends StatelessWidget {
  const TopBarNetworkModule({
    super.key,
    required this.networkKind,
    required this.onToggle,
    this.highlighted = false,
  });

  final NetworkKind networkKind;
  final ValueChanged<PanelAnchor> onToggle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Network',
    button: true,
    child: TopBarPanelTapTarget(
      alignment: PanelAlignment.right,
      onTap: onToggle,
      child: TopBarPill(
        icon: switch (networkKind) {
          NetworkKind.wifi => AliceIcons.wifi,
          NetworkKind.wired => AliceIcons.ethernet,
          NetworkKind.wifiDisconnected => AliceIcons.wifiDisconnected,
          NetworkKind.disconnected => AliceIcons.networkSlash,
        },
        label: '',
        highlighted: highlighted,
      ),
    ),
  );
}
