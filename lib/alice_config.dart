import 'package:flutter/material.dart';

class AliceConfig {
  const AliceConfig({
    required this.themeMode,
    required this.accentColor,
    required this.showNetworkLabel,
    required this.maxVisibleTrayItems,
    required this.localTimeZoneLabel,
    required this.timeZones,
    required this.powerCommands,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final bool showNetworkLabel;
  final int maxVisibleTrayItems;
  final String? localTimeZoneLabel;
  final List<TimeZoneConfig> timeZones;
  final PowerCommandConfig powerCommands;

  factory AliceConfig.fallback() {
    return const AliceConfig(
      themeMode: ThemeMode.system,
      accentColor: Color(0xFF4C956C),
      showNetworkLabel: true,
      maxVisibleTrayItems: 5,
      localTimeZoneLabel: null,
      timeZones: [
        TimeZoneConfig(label: 'UTC', offsetHours: 0),
        TimeZoneConfig(label: 'AEST', offsetHours: 10),
      ],
      powerCommands: PowerCommandConfig(
        lock: 'loginctl lock-session',
        lockAndSuspend: 'loginctl lock-session && systemctl suspend',
        restart: 'systemctl reboot',
        poweroff: 'systemctl poweroff',
      ),
    );
  }
}

class TimeZoneConfig {
  const TimeZoneConfig({required this.label, required this.offsetHours});

  final String label;
  final int offsetHours;
}

class PowerCommandConfig {
  const PowerCommandConfig({
    required this.lock,
    required this.lockAndSuspend,
    required this.restart,
    required this.poweroff,
  });

  final String lock;
  final String lockAndSuspend;
  final String restart;
  final String poweroff;
}
