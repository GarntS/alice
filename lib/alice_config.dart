import 'package:material_ui/material_ui.dart';

class AliceConfig {
  const AliceConfig({
    required this.themeMode,
    required this.accentColor,
    required this.transparentTopBar,
    required this.useDuotoneIcons,
    required this.useAccentOnIcons,
    required this.showNetworkLabel,
    required this.maxVisibleTrayItems,
    required this.localTimeZoneLabel,
    required this.timeZones,
    required this.powerCommands,
    required this.panelTopGapPx,
    required this.notifications,
    required this.weather,
    this.battery = const BatteryConfig(enable: true, deviceName: null),
    this.calendar,
    this.caldav,
  });

  final ThemeMode themeMode;
  final Color accentColor;
  final bool transparentTopBar;
  final bool useDuotoneIcons;
  final bool useAccentOnIcons;
  final bool showNetworkLabel;
  final int maxVisibleTrayItems;
  final String? localTimeZoneLabel;
  final List<TimeZoneConfig> timeZones;
  final PowerCommandConfig powerCommands;
  final int panelTopGapPx;
  final NotificationConfig notifications;
  final WeatherConfig weather;
  final BatteryConfig battery;
  final CalendarConfig? calendar;
  final CalDavConfig? caldav;

  factory AliceConfig.fallback() {
    return const AliceConfig(
      themeMode: ThemeMode.system,
      accentColor: Color(0xFF4C956C),
      transparentTopBar: false,
      useDuotoneIcons: true,
      useAccentOnIcons: true,
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
      weather: WeatherConfig(
        enable: true,
        pirateWeatherKey: null,
        forecastLat: null,
        forecastLong: null,
        forecastLanguage: 'en',
        forecastUnits: 'us',
        refreshInterval: 3600,
        locationLabel: null,
      ),
      battery: BatteryConfig(enable: true, deviceName: null),
    );
  }
}

class CalDavConfig {
  const CalDavConfig({
    required this.principalUrl,
    required this.allowHttp,
    required this.username,
    required this.collectionHrefs,
    required this.pollIntervalSecs,
    required this.caCertificatePath,
  });

  final String principalUrl;
  final bool allowHttp;
  final String username;
  final List<String> collectionHrefs;
  final int pollIntervalSecs;
  final String? caCertificatePath;
}

class WeatherConfig {
  const WeatherConfig({
    required this.enable,
    required this.pirateWeatherKey,
    required this.forecastLat,
    required this.forecastLong,
    required this.forecastLanguage,
    required this.forecastUnits,
    required this.refreshInterval,
    required this.locationLabel,
  });

  final bool enable;
  final String? pirateWeatherKey;
  final double? forecastLat;
  final double? forecastLong;
  final String forecastLanguage;
  final String forecastUnits;
  final int refreshInterval;
  final String? locationLabel;
}

class BatteryConfig {
  const BatteryConfig({required this.enable, required this.deviceName});

  final bool enable;
  final String? deviceName;
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

/// Secret-free calendar source metadata supplied by native configuration.
class CalendarConfig {
  const CalendarConfig({required this.calendars});

  final List<CalendarEntryConfig> calendars;
}

class CalendarEntryConfig {
  const CalendarEntryConfig({
    required this.id,
    required this.type,
    required this.color,
    required this.pollIntervalSecs,
    required this.notifyForEvents,
  });

  final String id;
  final String type;
  final String? color;
  final int pollIntervalSecs;

  /// Null for Google entries; ICS entries always expose their effective value.
  final bool? notifyForEvents;
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
