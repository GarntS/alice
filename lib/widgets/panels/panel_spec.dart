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
    AlicePanel.notifications => Size(
      380,
      _notificationPanelHeight(snapshot.notifications.length, screenHeight),
    ),
  };
}

double _mediaHeight(MediaSnapshot? media) {
  if (media == null) return 84.0;
  return media.artUrl.trim().isNotEmpty ? 268.0 : 228.0;
}

double _clockHeight(AliceConfig config, double screenHeight) {
  return screenHeight / 2;
}

double _notificationPanelHeight(int count, double screenHeight) {
  // 32 px outer padding + ~30 px title row + 8 px gap below title
  const overhead = 70.0;
  // Approximate per-card height (12 px padding × 2, header row, summary,
  // body, optional actions) plus the 6 px separator between cards.
  const cardHeight = 96.0;
  const cardSpacing = 6.0;
  const minHeight = 150.0;
  final maxHeight = (screenHeight - 60).clamp(400.0, 2000.0);

  if (count == 0) return minHeight;
  final content = overhead + count * cardHeight + (count - 1) * cardSpacing;
  return content.clamp(minHeight, maxHeight);
}

int _trayOverflowCount(AliceConfig config, BarSnapshot snapshot) {
  final visible = config.maxVisibleTrayItems > 0
      ? config.maxVisibleTrayItems - 1
      : 0;
  return math.max(0, snapshot.trayItems.length - visible);
}
