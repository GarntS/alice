import 'package:material_ui/material_ui.dart';

import '../alice_icon.dart';

import '../../rust_gen/state.dart';
import '../../panel_controller.dart';
import 'panel_tap_target.dart';
import 'pill.dart';

class TopBarMediaModule extends StatelessWidget {
  const TopBarMediaModule({
    super.key,
    required this.media,
    required this.highlighted,
    required this.onToggle,
  });

  final MediaSnapshot? media;
  final bool highlighted;
  final ValueChanged<PanelAnchor> onToggle;

  @override
  Widget build(BuildContext context) {
    if (media == null) {
      return const SizedBox.shrink();
    }

    return TopBarPanelTapTarget(
      alignment: PanelAlignment.center,
      onTap: onToggle,
      child: TopBarPill(
        icon: media!.isPlaying ? AliceIcons.play : AliceIcons.pause,
        label:
            '${media!.title} - ${media!.artist} - ${media!.positionLabel}/${media!.lengthLabel}',
        highlighted: highlighted,
      ),
    );
  }
}
