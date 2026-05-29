import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';

Size alicePanelSize(
  AlicePanel panel, {
  required AliceConfig config,
  required BarSnapshot snapshot,
  double screenHeight = 1080.0,
}) {
  return switch (panel) {
    AlicePanel.media => Size(360, _mediaHeight(snapshot.media)),
    AlicePanel.clock => Size(320, _clockHeight(config, screenHeight)),
    AlicePanel.trayOverflow => Size(
      320,
      (92 + (_trayOverflowCount(config, snapshot) * 52))
          .clamp(120, 320)
          .toDouble(),
    ),
    AlicePanel.power => const Size(280, 292),
    AlicePanel.notifications => const Size(380, 880),
  };
}

double _mediaHeight(MediaSnapshot? media) {
  if (media == null) return 84.0;
  return media.artUrl.trim().isNotEmpty ? 268.0 : 228.0;
}

double _clockHeight(AliceConfig config, double screenHeight) {
  return screenHeight / 2;
}

int _trayOverflowCount(AliceConfig config, BarSnapshot snapshot) {
  final visible = config.maxVisibleTrayItems > 0
      ? config.maxVisibleTrayItems - 1
      : 0;
  return math.max(0, snapshot.trayItems.length - visible);
}
