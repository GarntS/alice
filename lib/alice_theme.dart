import 'package:material_ui/material_ui.dart';

import 'alice_config.dart';

/// Alice-owned, brightness-specific color tokens.
@immutable
class AliceColorTokens extends ThemeExtension<AliceColorTokens> {
  const AliceColorTokens({
    required this.brightness,
    required this.accent,
    required this.onAccent,
    required this.accentSubtle,
    required this.accentBorder,
    required this.accentFocus,
    required this.accentHover,
    required this.accentPressed,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.raisedContainer,
    required this.error,
    required this.warning,
  });

  final Brightness brightness;
  final Color accent;
  final Color onAccent;
  final Color accentSubtle;
  final Color accentBorder;
  final Color accentFocus;
  final Color accentHover;
  final Color accentPressed;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color raisedContainer;
  final Color error;
  final Color warning;

  /// Returns the app palette, or Material role aliases for widgets hosted by
  /// external/default themes (such as isolated widget tests).
  static AliceColorTokens of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return theme.extension<AliceColorTokens>() ??
        AliceColorTokens(
          brightness: scheme.brightness,
          accent: scheme.primary,
          onAccent: scheme.onPrimary,
          accentSubtle: scheme.primaryContainer,
          accentBorder: scheme.outline,
          accentFocus: scheme.primary,
          accentHover: scheme.primaryContainer,
          accentPressed: scheme.outline,
          surface: scheme.surface,
          foreground: scheme.onSurface,
          muted: scheme.secondary,
          raisedContainer: scheme.secondaryContainer,
          error: scheme.error,
          warning: const Color(0xFFE9B44C),
        );
  }

  @override
  AliceColorTokens copyWith({
    Brightness? brightness,
    Color? accent,
    Color? onAccent,
    Color? accentSubtle,
    Color? accentBorder,
    Color? accentFocus,
    Color? accentHover,
    Color? accentPressed,
    Color? surface,
    Color? foreground,
    Color? muted,
    Color? raisedContainer,
    Color? error,
    Color? warning,
  }) => AliceColorTokens(
    brightness: brightness ?? this.brightness,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSubtle: accentSubtle ?? this.accentSubtle,
    accentBorder: accentBorder ?? this.accentBorder,
    accentFocus: accentFocus ?? this.accentFocus,
    accentHover: accentHover ?? this.accentHover,
    accentPressed: accentPressed ?? this.accentPressed,
    surface: surface ?? this.surface,
    foreground: foreground ?? this.foreground,
    muted: muted ?? this.muted,
    raisedContainer: raisedContainer ?? this.raisedContainer,
    error: error ?? this.error,
    warning: warning ?? this.warning,
  );

  @override
  AliceColorTokens lerp(covariant AliceColorTokens? other, double t) {
    if (other is! AliceColorTokens) return this;
    return AliceColorTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      accentFocus: Color.lerp(accentFocus, other.accentFocus, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      raisedContainer: Color.lerp(raisedContainer, other.raisedContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

AliceColorTokens buildAliceColorTokens(
  AliceConfig config,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF111417) : const Color(0xFFF6F3EA);
  final foreground = isDark ? const Color(0xFFF3F1EA) : const Color(0xFF181612);
  final muted = isDark ? const Color(0xFF2B3136) : const Color(0xFFE3DDCE);
  final accent = config.accentColor;

  Color blend(double opacity) =>
      Color.alphaBlend(accent.withValues(alpha: opacity), surface);

  return AliceColorTokens(
    brightness: brightness,
    accent: accent,
    onAccent: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black,
    accentSubtle: blend(0.14),
    accentBorder: blend(0.28),
    accentFocus: accent,
    accentHover: blend(0.20),
    accentPressed: blend(0.28),
    surface: surface,
    foreground: foreground,
    muted: muted,
    raisedContainer: blend(isDark ? 0.16 : 0.10),
    error: const Color(0xFFD1495B),
    warning: const Color(0xFFE9B44C),
  );
}

ThemeData buildAliceTheme(AliceConfig config, Brightness brightness) {
  final colors = buildAliceColorTokens(config, brightness);
  final scheme = _colorScheme(colors);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [colors],
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: ThemeData(brightness: brightness, fontFamily: 'NimbusSansDOT')
        .textTheme
        .apply(bodyColor: colors.foreground, displayColor: colors.foreground),
  );
}

ColorScheme _colorScheme(AliceColorTokens colors) => ColorScheme(
  brightness: colors.brightness,
  primary: colors.accent,
  onPrimary: colors.onAccent,
  primaryContainer: colors.accentSubtle,
  onPrimaryContainer: colors.foreground,
  primaryFixed: colors.accent,
  primaryFixedDim: colors.accentPressed,
  onPrimaryFixed: colors.onAccent,
  onPrimaryFixedVariant: colors.onAccent,
  secondary: colors.muted,
  onSecondary: colors.foreground,
  secondaryContainer: colors.raisedContainer,
  onSecondaryContainer: colors.foreground,
  secondaryFixed: colors.raisedContainer,
  secondaryFixedDim: colors.muted,
  onSecondaryFixed: colors.foreground,
  onSecondaryFixedVariant: colors.foreground,
  tertiary: colors.muted,
  onTertiary: colors.foreground,
  tertiaryContainer: colors.raisedContainer,
  onTertiaryContainer: colors.foreground,
  tertiaryFixed: colors.raisedContainer,
  tertiaryFixedDim: colors.muted,
  onTertiaryFixed: colors.foreground,
  onTertiaryFixedVariant: colors.foreground,
  error: colors.error,
  onError: Colors.black,
  errorContainer: colors.error.withValues(alpha: 0.15),
  onErrorContainer: colors.error,
  surface: colors.surface,
  onSurface: colors.foreground,
  surfaceDim: colors.surface,
  surfaceBright: colors.surface,
  surfaceContainerLowest: colors.surface,
  surfaceContainerLow: colors.surface,
  surfaceContainer: colors.raisedContainer,
  surfaceContainerHigh: colors.raisedContainer,
  surfaceContainerHighest: colors.raisedContainer,
  onSurfaceVariant: colors.foreground,
  outline: colors.accentBorder,
  outlineVariant: colors.muted,
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: colors.foreground,
  onInverseSurface: colors.surface,
  inversePrimary: colors.accent,
  surfaceTint: colors.accent,
);
