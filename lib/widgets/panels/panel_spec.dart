import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../alice_config.dart';
import '../../rust_gen/state.dart';
import '../../panel_controller.dart';

Size alicePanelSize(
  AlicePanel panel, {
  required AliceConfig config,
  required BarSnapshot snapshot,
}) {
  return switch (panel) {
    AlicePanel.media => const Size(360, 268),
    AlicePanel.clock => Size(320, config.timeZones.isEmpty ? 128 : 220),
    AlicePanel.trayOverflow => Size(
      320,
      (92 + (_trayOverflowCount(config, snapshot) * 52))
          .clamp(120, 320)
          .toDouble(),
    ),
    AlicePanel.power => const Size(280, 280),
  };
}

int _trayOverflowCount(AliceConfig config, BarSnapshot snapshot) {
  final visible = config.maxVisibleTrayItems > 0
      ? config.maxVisibleTrayItems - 1
      : 0;
  return math.max(0, snapshot.trayItems.length - visible);
}
