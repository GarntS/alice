import 'dart:typed_data';

import 'package:alicebar/alice_config.dart';
import 'package:alicebar/alice_theme.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultMediaSentinel = Object();

AliceConfig testConfig({
  int maxVisibleTrayItems = 3,
  bool showNetworkLabel = true,
  bool transparentTopBar = false,
  CalendarConfig? calendar,
  NotificationConfig notifications = const NotificationConfig(
    defaultTimeoutMs: 5000,
    showNotificationPopup: true,
    notificationDisplayTimeMs: 5000,
    expireCriticalNotifications: false,
  ),
}) {
  return AliceConfig(
    themeMode: ThemeMode.light,
    accentColor: const Color(0xFF4C956C),
    transparentTopBar: transparentTopBar,
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
    calendar: calendar,
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
  double memoryUsagePercent = 82,
  double cpuUsageCores = 2.7,
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
    trayItems: trayItems ?? testTrayItems(5),
    notifications: notifications ?? testNotifications(2),
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
  List<TrayItemSnapshot>? trayItems,
  List<NotificationSnapshot>? notifications,
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
    trayItems: trayItems ?? snapshot.trayItems,
    notifications: notifications ?? snapshot.notifications,
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
  final state = AliceSnapshotState(config: config ?? testConfig());
  state.ingest(snapshot ?? testSnapshot());
  return state;
}

Future<void> pumpAliceWidget(
  WidgetTester tester,
  Widget child, {
  AliceConfig? config,
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final c = config ?? testConfig();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAliceTheme(c, Brightness.light),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: child),
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
