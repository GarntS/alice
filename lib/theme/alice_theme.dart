import 'package:flutter/material.dart';

import '../data/alice_config.dart';

ThemeData buildAliceTheme(AliceConfig config, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF111417) : const Color(0xFFF6F3EA);
  final foreground = isDark ? const Color(0xFFF3F1EA) : const Color(0xFF181612);
  final muted = isDark ? const Color(0xFF2B3136) : const Color(0xFFE3DDCE);

  final scheme = ColorScheme.fromSeed(
    seedColor: config.accentColor,
    brightness: brightness,
    surface: surface,
  ).copyWith(onSurface: foreground, secondary: muted, onSecondary: foreground);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground),
  );
}
