import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../alice_config.dart';

/// A semantic Phosphor icon represented in both supported presentation styles.
class AliceIconDescriptor {
  const AliceIconDescriptor({required this.regular, required this.duotone});

  final IconData regular;
  final PhosphorDuotoneIconData duotone;
}

/// Makes Alice's icon presentation preferences available to descendant icons.
class AliceIcons {
  const AliceIcons._();

  static const clock = AliceIconDescriptor(
    regular: PhosphorIconsRegular.clock,
    duotone: PhosphorIconsDuotone.clock,
  );
  static const cpu = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cpu,
    duotone: PhosphorIconsDuotone.cpu,
  );
  static const memory = AliceIconDescriptor(
    regular: PhosphorIconsRegular.memory,
    duotone: PhosphorIconsDuotone.memory,
  );
  static const batteryFull = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryFull,
    duotone: PhosphorIconsDuotone.batteryFull,
  );
  static const batteryHigh = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryHigh,
    duotone: PhosphorIconsDuotone.batteryHigh,
  );
  static const batteryMedium = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryMedium,
    duotone: PhosphorIconsDuotone.batteryMedium,
  );
  static const batteryLow = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryLow,
    duotone: PhosphorIconsDuotone.batteryLow,
  );
  static const batteryWarning = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryWarning,
    duotone: PhosphorIconsDuotone.batteryWarning,
  );
  static const batteryCharging = AliceIconDescriptor(
    regular: PhosphorIconsRegular.batteryCharging,
    duotone: PhosphorIconsDuotone.batteryCharging,
  );
  static const play = AliceIconDescriptor(
    regular: PhosphorIconsRegular.play,
    duotone: PhosphorIconsDuotone.play,
  );
  static const pause = AliceIconDescriptor(
    regular: PhosphorIconsRegular.pause,
    duotone: PhosphorIconsDuotone.pause,
  );
  static const wifi = AliceIconDescriptor(
    regular: PhosphorIconsRegular.wifiHigh,
    duotone: PhosphorIconsDuotone.wifiHigh,
  );
  static const link = AliceIconDescriptor(
    regular: PhosphorIconsRegular.link,
    duotone: PhosphorIconsDuotone.link,
  );
  static const at = AliceIconDescriptor(
    regular: PhosphorIconsRegular.at,
    duotone: PhosphorIconsDuotone.at,
  );
  static const keyhole = AliceIconDescriptor(
    regular: PhosphorIconsRegular.keyhole,
    duotone: PhosphorIconsDuotone.keyhole,
  );
  static const ethernet = AliceIconDescriptor(
    regular: PhosphorIconsRegular.network,
    duotone: PhosphorIconsDuotone.network,
  );
  static const wifiDisconnected = AliceIconDescriptor(
    regular: PhosphorIconsRegular.wifiX,
    duotone: PhosphorIconsDuotone.wifiX,
  );
  static const networkSlash = AliceIconDescriptor(
    regular: PhosphorIconsRegular.networkX,
    duotone: PhosphorIconsDuotone.networkX,
  );
  static const cloud = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloud,
    duotone: PhosphorIconsDuotone.cloud,
  );
  static const sun = AliceIconDescriptor(
    regular: PhosphorIconsRegular.sun,
    duotone: PhosphorIconsDuotone.sun,
  );
  static const moon = AliceIconDescriptor(
    regular: PhosphorIconsRegular.moon,
    duotone: PhosphorIconsDuotone.moon,
  );
  static const cloudSun = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudSun,
    duotone: PhosphorIconsDuotone.cloudSun,
  );
  static const cloudMoon = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudMoon,
    duotone: PhosphorIconsDuotone.cloudMoon,
  );
  static const cloudRain = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudRain,
    duotone: PhosphorIconsDuotone.cloudRain,
  );
  static const cloudSnow = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudSnow,
    duotone: PhosphorIconsDuotone.cloudSnow,
  );
  static const cloudFog = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudFog,
    duotone: PhosphorIconsDuotone.cloudFog,
  );
  static const drop = AliceIconDescriptor(
    regular: PhosphorIconsRegular.drop,
    duotone: PhosphorIconsDuotone.drop,
  );
  static const wind = AliceIconDescriptor(
    regular: PhosphorIconsRegular.wind,
    duotone: PhosphorIconsDuotone.wind,
  );
  static const compass = AliceIconDescriptor(
    regular: PhosphorIconsRegular.compass,
    duotone: PhosphorIconsDuotone.compass,
  );
  static const arrowUp = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowUp,
    duotone: PhosphorIconsDuotone.arrowUp,
  );
  static const arrowUpRight = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowUpRight,
    duotone: PhosphorIconsDuotone.arrowUpRight,
  );
  static const arrowRight = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowRight,
    duotone: PhosphorIconsDuotone.arrowRight,
  );
  static const arrowDownRight = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowDownRight,
    duotone: PhosphorIconsDuotone.arrowDownRight,
  );
  static const arrowDown = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowDown,
    duotone: PhosphorIconsDuotone.arrowDown,
  );
  static const arrowDownLeft = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowDownLeft,
    duotone: PhosphorIconsDuotone.arrowDownLeft,
  );
  static const arrowLeft = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowLeft,
    duotone: PhosphorIconsDuotone.arrowLeft,
  );
  static const arrowUpLeft = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowUpLeft,
    duotone: PhosphorIconsDuotone.arrowUpLeft,
  );
  static const bell = AliceIconDescriptor(
    regular: PhosphorIconsRegular.bell,
    duotone: PhosphorIconsDuotone.bell,
  );
  static const power = AliceIconDescriptor(
    regular: PhosphorIconsRegular.power,
    duotone: PhosphorIconsDuotone.power,
  );
  static const listChecks = AliceIconDescriptor(
    regular: PhosphorIconsRegular.listChecks,
    duotone: PhosphorIconsDuotone.listChecks,
  );
  static const warningCircle = AliceIconDescriptor(
    regular: PhosphorIconsRegular.warningCircle,
    duotone: PhosphorIconsDuotone.warningCircle,
  );
  static const dotsNine = AliceIconDescriptor(
    regular: PhosphorIconsRegular.dotsNine,
    duotone: PhosphorIconsDuotone.dotsNine,
  );
  static const caretDown = AliceIconDescriptor(
    regular: PhosphorIconsRegular.caretDown,
    duotone: PhosphorIconsDuotone.caretDown,
  );
  static const caretLeft = AliceIconDescriptor(
    regular: PhosphorIconsRegular.caretLeft,
    duotone: PhosphorIconsDuotone.caretLeft,
  );
  static const caretRight = AliceIconDescriptor(
    regular: PhosphorIconsRegular.caretRight,
    duotone: PhosphorIconsDuotone.caretRight,
  );
  static const close = AliceIconDescriptor(
    regular: PhosphorIconsRegular.x,
    duotone: PhosphorIconsDuotone.x,
  );
  static const copy = AliceIconDescriptor(
    regular: PhosphorIconsRegular.copy,
    duotone: PhosphorIconsDuotone.copy,
  );
  static const folder = AliceIconDescriptor(
    regular: PhosphorIconsRegular.folder,
    duotone: PhosphorIconsDuotone.folder,
  );
  static const lock = AliceIconDescriptor(
    regular: PhosphorIconsRegular.lock,
    duotone: PhosphorIconsDuotone.lock,
  );
  static const bed = AliceIconDescriptor(
    regular: PhosphorIconsRegular.bed,
    duotone: PhosphorIconsDuotone.bed,
  );
  static const refresh = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowClockwise,
    duotone: PhosphorIconsDuotone.arrowClockwise,
  );
  static const sync = AliceIconDescriptor(
    regular: PhosphorIconsRegular.arrowsClockwise,
    duotone: PhosphorIconsDuotone.arrowsClockwise,
  );
  static const cloudSlash = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudSlash,
    duotone: PhosphorIconsDuotone.cloudSlash,
  );
  static const checkCircle = AliceIconDescriptor(
    regular: PhosphorIconsRegular.checkCircle,
    duotone: PhosphorIconsDuotone.checkCircle,
  );
  static const calendar = AliceIconDescriptor(
    regular: PhosphorIconsRegular.calendar,
    duotone: PhosphorIconsDuotone.calendar,
  );
  static const cloudCheck = AliceIconDescriptor(
    regular: PhosphorIconsRegular.cloudCheck,
    duotone: PhosphorIconsDuotone.cloudCheck,
  );
  static const skipBack = AliceIconDescriptor(
    regular: PhosphorIconsRegular.skipBack,
    duotone: PhosphorIconsDuotone.skipBack,
  );
  static const skipForward = AliceIconDescriptor(
    regular: PhosphorIconsRegular.skipForward,
    duotone: PhosphorIconsDuotone.skipForward,
  );
  static const musicNote = AliceIconDescriptor(
    regular: PhosphorIconsRegular.musicNote,
    duotone: PhosphorIconsDuotone.musicNote,
  );
  static const circle = AliceIconDescriptor(
    regular: PhosphorIconsRegular.circle,
    duotone: PhosphorIconsDuotone.circle,
  );
  static const circleHalf = AliceIconDescriptor(
    regular: PhosphorIconsRegular.circleHalf,
    duotone: PhosphorIconsDuotone.circleHalf,
  );
  static const dropHalf = AliceIconDescriptor(
    regular: PhosphorIconsRegular.dropHalf,
    duotone: PhosphorIconsDuotone.dropHalf,
  );
  static const dropSimple = AliceIconDescriptor(
    regular: PhosphorIconsRegular.dropSimple,
    duotone: PhosphorIconsDuotone.dropSimple,
  );
  static const dropSlash = AliceIconDescriptor(
    regular: PhosphorIconsRegular.dropSlash,
    duotone: PhosphorIconsDuotone.dropSlash,
  );
}

class AliceIconTheme extends InheritedWidget {
  const AliceIconTheme({super.key, required this.config, required super.child});

  final AliceConfig config;

  static AliceConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AliceIconTheme>()?.config ??
      AliceConfig.fallback();

  @override
  bool updateShouldNotify(AliceIconTheme oldWidget) =>
      config != oldWidget.config;
}

/// Renders an Alice-owned Phosphor icon using the configured style and colors.
class AliceIcon extends StatelessWidget {
  const AliceIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AliceIconDescriptor icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final config = AliceIconTheme.of(context);
    if (!config.useDuotoneIcons) {
      return Icon(
        icon.regular,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
    }

    final secondaryColor = config.useAccentOnIcons
        ? config.accentColor
        : Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF6B7280);
    return PhosphorIcon(
      icon.duotone,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      duotoneSecondaryColor: secondaryColor,
    );
  }
}
