import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import '../../rust_gen/state.dart';
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
        NetworkKind.wifi => AliceIcons.wifi,
        NetworkKind.wired => AliceIcons.ethernet,
        NetworkKind.disconnected => AliceIcons.networkSlash,
      },
      label: label,
    );
  }
}
