import 'dart:typed_data';

import 'package:alicebar/alice_config.dart';
import 'package:alicebar/alice_theme.dart';
import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultMediaSentinel = Object();

AliceConfig testConfig({
  int maxVisibleTrayItems = 3,
  bool showNetworkLabel = true,
  bool transparentTopBar = false,
  bool useDuotoneIcons = true,
  bool useAccentOnIcons = true,
  Color accentColor = const Color(0xFF4C956C),
  CalendarConfig? calendar,
  CalDavConfig? caldav,
  WeatherConfig weather = const WeatherConfig(
    enable: true,
    pirateWeatherKey: null,
    forecastLat: null,
    forecastLong: null,
    forecastLanguage: 'en',
    forecastUnits: 'us',
    refreshInterval: 3600,
    locationLabel: null,
  ),
  NotificationConfig notifications = const NotificationConfig(
    defaultTimeoutMs: 5000,
    showNotificationPopup: true,
    notificationDisplayTimeMs: 5000,
    expireCriticalNotifications: false,
  ),
}) {
  return AliceConfig(
    themeMode: ThemeMode.light,
    accentColor: accentColor,
    transparentTopBar: transparentTopBar,
    useDuotoneIcons: useDuotoneIcons,
    useAccentOnIcons: useAccentOnIcons,
    showNetworkLabel: showNetworkLabel,
    maxVisibleTrayItems: maxVisibleTrayItems,
    localTimeZoneLabel: 'LOCAL',
    timeZones: const [
      TimeZoneConfig(label: 'UTC', offsetHours: 0),
      TimeZoneConfig(label: 'JST', offsetHours: 9),
    ],
    powerCommands: const PowerCommandConfig(
      lock: 'lock',
      lockAndSuspend: 'lock-suspend',
      restart: 'restart',
      poweroff: 'poweroff',
    ),
    panelTopGapPx: 8,
    notifications: notifications,
    weather: weather,
    calendar: calendar,
    caldav: caldav,
  );
}

BarSnapshot testSnapshot({
  List<WorkspaceSnapshot>? workspaces,
  Object? media = _defaultMediaSentinel,
  List<TrayItemSnapshot>? trayItems,
  List<NotificationSnapshot>? notifications,
  NetworkSnapshot? network,
  ClockSnapshot clock = const ClockSnapshot(
    timeZoneCode: 'UTC',
    dateLabel: '09 Mar',
    timeLabel: '13:37',
  ),
  WeatherSnapshot? weather,
  BatterySnapshot? battery,
  double memoryUsagePercent = 82,
  double cpuUsageCores = 2.7,
  List<NormalizedTask> tasks = const [],
  CalDavSyncState caldavSyncState = const CalDavSyncState(
    freshness: CalDavFreshness.disabled,
    hasCachedData: false,
  ),
}) {
  final resolvedMedia = identical(media, _defaultMediaSentinel)
      ? testMedia()
      : media as MediaSnapshot?;
  return BarSnapshot(
    workspaces: workspaces ?? testWorkspaces(),
    media: resolvedMedia,
    memoryUsagePercent: memoryUsagePercent,
    cpuUsageCores: cpuUsageCores,
    network:
        network ??
        const NetworkSnapshot(kind: NetworkKind.wifi, label: 'alice-net'),
    clock: clock,
    weather: weather,
    battery: battery,
    trayItems: trayItems ?? testTrayItems(5),
    notifications: notifications ?? testNotifications(2),
    tasks: tasks,
    caldavSyncState: caldavSyncState,
  );
}

BarSnapshot copyTestSnapshot(
  BarSnapshot snapshot, {
  List<WorkspaceSnapshot>? workspaces,
  Object? media = _defaultMediaSentinel,
  double? memoryUsagePercent,
  double? cpuUsageCores,
  NetworkSnapshot? network,
  ClockSnapshot? clock,
  WeatherSnapshot? weather,
  BatterySnapshot? battery,
  List<TrayItemSnapshot>? trayItems,
  List<NotificationSnapshot>? notifications,
  List<NormalizedTask>? tasks,
  CalDavSyncState? caldavSyncState,
}) {
  return BarSnapshot(
    workspaces: workspaces ?? snapshot.workspaces,
    media: identical(media, _defaultMediaSentinel)
        ? snapshot.media
        : media as MediaSnapshot?,
    memoryUsagePercent: memoryUsagePercent ?? snapshot.memoryUsagePercent,
    cpuUsageCores: cpuUsageCores ?? snapshot.cpuUsageCores,
    network: network ?? snapshot.network,
    clock: clock ?? snapshot.clock,
    weather: weather ?? snapshot.weather,
    battery: battery ?? snapshot.battery,
    trayItems: trayItems ?? snapshot.trayItems,
    notifications: notifications ?? snapshot.notifications,
    tasks: tasks ?? snapshot.tasks,
    caldavSyncState: caldavSyncState ?? snapshot.caldavSyncState,
  );
}

List<WorkspaceSnapshot> testWorkspaces() => const [
  WorkspaceSnapshot(label: '1', isFocused: true, isVisible: true),
  WorkspaceSnapshot(label: '2', isFocused: false, isVisible: true),
  WorkspaceSnapshot(label: '3', isFocused: false, isVisible: false),
];

MediaSnapshot testMedia({
  int positionMicros = 26 * 1000 * 1000,
  int lengthMicros = 130 * 1000 * 1000,
  String albumTitle = 'Boundary Album',
  String artUrl = '',
}) {
  return MediaSnapshot(
    title: 'A Very Testable Song',
    artist: 'Alice Artist',
    albumTitle: albumTitle,
    artUrl: artUrl,
    positionLabel: '0:26',
    lengthLabel: '2:10',
    positionMicros: positionMicros,
    lengthMicros: lengthMicros,
    isPlaying: true,
  );
}

WeatherSnapshot testWeather() {
  const now = 1780183620;
  return const WeatherSnapshot(
    latitude: 43.407,
    longitude: -70.996,
    timezone: 'America/New_York',
    offset: -4,
    units: 'us',
    lastUpdatedUnixSecs: now,
    currently: WeatherPoint(
      time: now,
      summary: 'Clear',
      icon: 'clear-day',
      temperature: 50.25,
      humidity: 0.72,
      precipProbability: 0.32,
      windSpeed: 4.52,
      windBearing: 48,
    ),
    hourly: [
      WeatherPoint(
        time: now - 3600,
        summary: 'Partly Cloudy',
        icon: 'partly-cloudy-day',
        temperature: 50.09,
        humidity: 0.65,
        precipProbability: 0,
        windSpeed: 5.58,
        windBearing: 40,
      ),
      WeatherPoint(
        time: now + 3600,
        summary: 'Mostly Clear',
        icon: 'clear-day',
        temperature: 48.29,
        humidity: 0.72,
        precipProbability: 0,
        windSpeed: 2.46,
        windBearing: 20,
      ),
    ],
    daily: [
      WeatherDay(
        time: now,
        summary: 'Windy in the morning.',
        icon: 'wind',
        moonPhase: 0.48,
        temperatureHigh: 50.45,
        temperatureLow: 40.37,
        humidity: 0.87,
        precipProbability: 0,
        windSpeed: 14.28,
        windBearing: 84,
      ),
      WeatherDay(
        time: now + 86400,
        summary: 'Light rain.',
        icon: 'rain',
        moonPhase: 0.5,
        temperatureHigh: 61.43,
        temperatureLow: 46.67,
        humidity: 0.74,
        precipProbability: 0.36,
        windSpeed: 5.19,
        windBearing: 299,
      ),
    ],
    alerts: [],
  );
}

List<TrayItemSnapshot> testTrayItems(int count, {Uint8List? iconBytes}) {
  return List.generate(
    count,
    (i) => TrayItemSnapshot(
      id: 'tray-$i',
      label: 'Tray Item $i',
      serviceName: 'org.kde.StatusNotifierItem.test$i',
      objectPath: '/StatusNotifierItem',
      iconPngBytes: iconBytes,
    ),
  );
}

List<NotificationSnapshot> testNotifications(
  int count, {
  Uint8List? imageData,
}) {
  final now = BigInt.from(1770000000);
  return List.generate(
    count,
    (i) => NotificationSnapshot(
      id: i + 1,
      appName: 'Notifier $i',
      appIcon: '',
      summary: 'Summary $i',
      body:
          'A long-ish notification body that should wrap without crashing the panel layout.',
      urgency: i.isEven
          ? NotificationUrgency.normal
          : NotificationUrgency.critical,
      actions: const [
        NotificationActionSnapshot(key: 'default', label: 'Open'),
        NotificationActionSnapshot(key: 'dismiss', label: 'Dismiss'),
      ],
      category: 'email',
      isRead: i.isEven,
      receivedAtUnixSecs: now - BigInt.from(i * 60),
      imageData: imageData,
      imagePath: null,
    ),
  );
}

AliceSnapshotState testSnapshotState({
  AliceConfig? config,
  BarSnapshot? snapshot,
}) {
  final state = AliceSnapshotState(
    config: config ?? testConfig(),
    scheduleDateRollover: false,
  );
  state.ingest(snapshot ?? testSnapshot());
  return state;
}

Future<void> pumpAliceWidget(
  WidgetTester tester,
  Widget child, {
  AliceConfig? config,
  Brightness brightness = Brightness.light,
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final c = config ?? testConfig();
  await tester.pumpWidget(
    MaterialApp(
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      theme: buildAliceTheme(c, brightness),
      darkTheme: buildAliceTheme(c, brightness),
      home: Theme(
        data: buildAliceTheme(c, brightness),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AliceIconTheme(
            config: c,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void expectNoFlutterErrors() {
  expect(TestWidgetsFlutterBinding.instance.takeException(), isNull);
}

class BuildCounter extends StatelessWidget {
  const BuildCounter({
    super.key,
    required this.name,
    required this.counts,
    required this.child,
  });

  final String name;
  final Map<String, int> counts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    counts[name] = (counts[name] ?? 0) + 1;
    return child;
  }
}
