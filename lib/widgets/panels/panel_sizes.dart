import 'package:material_ui/material_ui.dart';

import '../../panel_controller.dart';

Size alicePanelSize(AlicePanel panel) {
  return switch (panel) {
    AlicePanel.media => const Size(360, 268),
    AlicePanel.clock => const Size(320, 700),
    AlicePanel.tasks => const Size(380, 800),
    AlicePanel.weather => const Size(320, 600),
    AlicePanel.trayOverflow => const Size(320, 320),
    AlicePanel.power => const Size(280, 300),
    AlicePanel.notifications => const Size(380, 880),
  };
}
