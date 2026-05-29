import 'package:flutter/material.dart';

class AliceConfig {
  const AliceConfig({
    required this.themeMode,
    required this.accentColor,
    required this.transparentTopBar,
    required this.showNetworkLabel,
    required this.maxVisibleTrayItems,
    required this.localTimeZoneLabel,
    required this.timeZones,
    required this.powerCommands,
    required this.panelTopGapPx,
    required this.notifications,
    this.calendar,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final bool transparentTopBar;
  final bool showNetworkLabel;
  final int maxVisibleTrayItems;
  final String? localTimeZoneLabel;
  final List<TimeZoneConfig> timeZones;
  final PowerCommandConfig powerCommands;
  final int panelTopGapPx;
  final NotificationConfig notifications;
  final CalendarConfig? calendar;

  factory AliceConfig.fallback() {
    return const AliceConfig(
      themeMode: ThemeMode.system,
      accentColor: Color(0xFF4C956C),
      transparentTopBar: false,
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
      panelTopGapPx: 8,
      notifications: NotificationConfig(
        defaultTimeoutMs: 5000,
        showNotificationPopup: true,
        notificationDisplayTimeMs: 5000,
        expireCriticalNotifications: false,
      ),
    );
  }
}

class NotificationConfig {
  const NotificationConfig({
    required this.defaultTimeoutMs,
    required this.showNotificationPopup,
    required this.notificationDisplayTimeMs,
    required this.expireCriticalNotifications,
  });

  final int defaultTimeoutMs;
  final bool showNotificationPopup;
  final int notificationDisplayTimeMs;
  final bool expireCriticalNotifications;
}

class TimeZoneConfig {
  const TimeZoneConfig({required this.label, required this.offsetHours});

  final String label;
  final int offsetHours;
}

class CalendarConfig {
  const CalendarConfig({
    required this.googleClientId,
    required this.googleClientSecret,
  });

  final String googleClientId;
  final String googleClientSecret;
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
