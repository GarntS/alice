import 'dart:typed_data';

import 'package:alicebar/alice_config.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  test(
    'equivalent generated list contents do not notify for new list instances',
    () {
      final state = AliceSnapshotState(
        config: testConfig(maxVisibleTrayItems: 3),
      );
      addTearDown(state.dispose);
      state.ingest(testSnapshot());

      var workspaces = 0;
      var tray = 0;
      var notifications = 0;
      state.workspaces.addListener(() => workspaces++);
      state.trayItems.addListener(() => tray++);
      state.notifications.addListener(() => notifications++);

      state.ingest(testSnapshot());

      expect(workspaces, 0);
      expect(tray, 0);
      expect(notifications, 0);
    },
  );

  test(
    'weather comparison detects offset changes and ignores fresh equivalents',
    () {
      final baseWeather = _freshWeather(
        testWeather(),
        alerts: const [
          WeatherAlert(
            title: 'Wind advisory',
            description: 'Strong gusts expected.',
            severity: 'moderate',
            time: 1780183620,
            expires: 1780187220,
          ),
        ],
      );
      final state = AliceSnapshotState(config: testConfig());
      addTearDown(state.dispose);
      state.ingest(testSnapshot(weather: baseWeather));

      var weatherNotifications = 0;
      var workspaceNotifications = 0;
      var trayNotifications = 0;
      var notificationNotifications = 0;
      state.weather.addListener(() => weatherNotifications++);
      state.workspaces.addListener(() => workspaceNotifications++);
      state.trayItems.addListener(() => trayNotifications++);
      state.notifications.addListener(() => notificationNotifications++);

      state.ingest(
        copySnapshot(
          state.currentSnapshot,
          weather: _freshWeather(baseWeather),
        ),
      );

      expect(weatherNotifications, 0);
      expect(workspaceNotifications, 0);
      expect(trayNotifications, 0);
      expect(notificationNotifications, 0);

      state.ingest(
        copySnapshot(
          state.currentSnapshot,
          weather: _freshWeather(baseWeather, offset: -5),
        ),
      );

      expect(weatherNotifications, 1);
      expect(state.currentWeather?.offset, -5);
      expect(workspaceNotifications, 0);
      expect(trayNotifications, 0);
      expect(notificationNotifications, 0);
    },
  );

  test('raw slice notifications are isolated', () {
    final state = AliceSnapshotState(config: testConfig());
    addTearDown(state.dispose);
    final base = testSnapshot();
    state.ingest(base);

    final counts = <String, int>{};
    void count(String name) => counts[name] = (counts[name] ?? 0) + 1;
    state.cpuUsageCores.addListener(() => count('cpu'));
    state.memoryUsagePercent.addListener(() => count('memory'));
    state.media.addListener(() => count('media'));
    state.clock.addListener(() => count('clock'));
    state.network.addListener(() => count('network'));
    state.workspaces.addListener(() => count('workspaces'));
    state.trayItems.addListener(() => count('tray'));
    state.notifications.addListener(() => count('notifications'));

    state.ingest(copySnapshot(base, cpuUsageCores: 9.1));
    expect(counts, {'cpu': 1});

    state.ingest(copySnapshot(state.currentSnapshot, memoryUsagePercent: 12));
    expect(counts['memory'], 1);
    expect(counts.length, 2);

    state.ingest(
      copySnapshot(
        state.currentSnapshot,
        media: testMedia(albumTitle: 'Other'),
      ),
    );
    expect(counts['media'], 1);
    expect(counts.length, 3);

    state.ingest(
      copySnapshot(
        state.currentSnapshot,
        clock: const ClockSnapshot(
          timeZoneCode: 'UTC',
          dateLabel: '10 Mar',
          timeLabel: '13:38',
        ),
      ),
    );
    expect(counts['clock'], 1);
    expect(counts.length, 4);

    state.ingest(
      copySnapshot(
        state.currentSnapshot,
        network: const NetworkSnapshot(kind: NetworkKind.wired, label: 'eth0'),
      ),
    );
    expect(counts['network'], 1);
    expect(counts.length, 5);

    state.ingest(
      copySnapshot(
        state.currentSnapshot,
        workspaces: [
          const WorkspaceSnapshot(
            label: '1',
            isFocused: false,
            isVisible: true,
          ),
        ],
      ),
    );
    expect(counts['workspaces'], 1);
    expect(counts.length, 6);

    state.ingest(
      copySnapshot(state.currentSnapshot, trayItems: testTrayItems(1)),
    );
    expect(counts['tray'], 1);
    expect(counts.length, 7);

    state.ingest(
      copySnapshot(state.currentSnapshot, notifications: testNotifications(3)),
    );
    expect(counts['notifications'], 1);
    expect(counts.length, 8);
  });

  test('derived notification and tray projections notify narrowly', () {
    final state = AliceSnapshotState(
      config: testConfig(maxVisibleTrayItems: 3),
    );
    addTearDown(state.dispose);
    state.ingest(
      testSnapshot(
        trayItems: testTrayItems(4),
        notifications: testNotifications(2),
      ),
    );
    state.updatePopupVisibleIds(const [1]);

    expect(state.currentVisibleTrayItems.length, 2);
    expect(state.currentTrayOverflowCount, 2);
    expect(state.unreadNotificationCount.value, 1);
    expect(state.popupNotifications.value.map((n) => n.id), [1]);

    var unread = 0;
    var popup = 0;
    var visibleTray = 0;
    var overflow = 0;
    state.unreadNotificationCount.addListener(() => unread++);
    state.popupNotifications.addListener(() => popup++);
    state.visibleTrayItems.addListener(() => visibleTray++);
    state.trayOverflowCount.addListener(() => overflow++);

    final changedBody = testNotifications(2)
        .map(
          (n) => n.id == 1
              ? NotificationSnapshot(
                  id: n.id,
                  appName: n.appName,
                  appIcon: n.appIcon,
                  summary: '${n.summary} changed',
                  body: n.body,
                  urgency: n.urgency,
                  actions: n.actions,
                  category: n.category,
                  isRead: n.isRead,
                  receivedAtUnixSecs: n.receivedAtUnixSecs,
                  imageData: n.imageData,
                  imagePath: n.imagePath,
                )
              : n,
        )
        .toList();
    state.ingest(
      copySnapshot(state.currentSnapshot, notifications: changedBody),
    );
    expect(unread, 0);
    expect(popup, 1);
    expect(state.popupNotifications.value.single.summary, 'Summary 0 changed');

    state.updateConfig(testConfig(maxVisibleTrayItems: 5));
    expect(visibleTray, 1);
    expect(overflow, 1);
  });

  test('explicit config updates recompute tray and popup projections', () {
    final state = AliceSnapshotState(
      config: testConfig(maxVisibleTrayItems: 3),
    );
    addTearDown(state.dispose);
    state.ingest(
      testSnapshot(
        trayItems: testTrayItems(4),
        notifications: testNotifications(1),
      ),
    );
    state.updatePopupVisibleIds(const [1]);

    var visibleTrayNotifications = 0;
    var popupNotifications = 0;
    state.visibleTrayItems.addListener(() => visibleTrayNotifications++);
    state.popupNotifications.addListener(() => popupNotifications++);

    state.updateConfig(
      testConfig(
        maxVisibleTrayItems: 5,
        notifications: const NotificationConfig(
          defaultTimeoutMs: 5000,
          showNotificationPopup: false,
          notificationDisplayTimeMs: 5000,
          expireCriticalNotifications: false,
        ),
      ),
    );

    expect(state.currentVisibleTrayItems.length, 4);
    expect(state.currentTrayOverflowCount, 0);
    expect(state.popupNotifications.value, isEmpty);
    expect(visibleTrayNotifications, 1);
    expect(popupNotifications, 1);

    state.updateConfig(testConfig(maxVisibleTrayItems: 5));

    expect(
      state.popupNotifications.value.map((notification) => notification.id),
      [1],
    );
    expect(visibleTrayNotifications, 1);
    expect(popupNotifications, 2);
  });

  test('binary data compares by bytes, not list identity', () {
    final state = AliceSnapshotState(config: testConfig());
    addTearDown(state.dispose);
    state.ingest(
      testSnapshot(
        trayItems: testTrayItems(1, iconBytes: Uint8List.fromList([1, 2, 3])),
        notifications: testNotifications(
          1,
          imageData: Uint8List.fromList([4, 5, 6]),
        ),
      ),
    );
    var tray = 0;
    var notifications = 0;
    state.trayItems.addListener(() => tray++);
    state.notifications.addListener(() => notifications++);

    state.ingest(
      testSnapshot(
        trayItems: testTrayItems(1, iconBytes: Uint8List.fromList([1, 2, 3])),
        notifications: testNotifications(
          1,
          imageData: Uint8List.fromList([4, 5, 6]),
        ),
      ),
    );

    expect(tray, 0);
    expect(notifications, 0);
  });
}

BarSnapshot copySnapshot(
  BarSnapshot snapshot, {
  List<WorkspaceSnapshot>? workspaces,
  Object? media = _sentinel,
  double? memoryUsagePercent,
  double? cpuUsageCores,
  NetworkSnapshot? network,
  ClockSnapshot? clock,
  WeatherSnapshot? weather,
  List<TrayItemSnapshot>? trayItems,
  List<NotificationSnapshot>? notifications,
}) {
  return BarSnapshot(
    workspaces: workspaces ?? snapshot.workspaces,
    media: identical(media, _sentinel)
        ? snapshot.media
        : media as MediaSnapshot?,
    memoryUsagePercent: memoryUsagePercent ?? snapshot.memoryUsagePercent,
    cpuUsageCores: cpuUsageCores ?? snapshot.cpuUsageCores,
    network: network ?? snapshot.network,
    clock: clock ?? snapshot.clock,
    weather: weather ?? snapshot.weather,
    trayItems: trayItems ?? snapshot.trayItems,
    notifications: notifications ?? snapshot.notifications,
  );
}

WeatherSnapshot _freshWeather(
  WeatherSnapshot source, {
  double? offset,
  List<WeatherAlert>? alerts,
}) {
  WeatherPoint copyPoint(WeatherPoint point) => WeatherPoint(
    time: point.time,
    summary: point.summary,
    icon: point.icon,
    temperature: point.temperature,
    humidity: point.humidity,
    precipProbability: point.precipProbability,
    windSpeed: point.windSpeed,
    windBearing: point.windBearing,
  );

  return WeatherSnapshot(
    latitude: source.latitude,
    longitude: source.longitude,
    timezone: source.timezone,
    offset: offset ?? source.offset,
    units: source.units,
    lastUpdatedUnixSecs: source.lastUpdatedUnixSecs,
    currently: copyPoint(source.currently),
    hourly: source.hourly.map(copyPoint).toList(),
    daily: source.daily
        .map(
          (day) => WeatherDay(
            time: day.time,
            summary: day.summary,
            icon: day.icon,
            moonPhase: day.moonPhase,
            temperatureHigh: day.temperatureHigh,
            temperatureLow: day.temperatureLow,
            humidity: day.humidity,
            precipProbability: day.precipProbability,
            windSpeed: day.windSpeed,
            windBearing: day.windBearing,
          ),
        )
        .toList(),
    alerts: (alerts ?? source.alerts)
        .map(
          (alert) => WeatherAlert(
            title: alert.title,
            description: alert.description,
            severity: alert.severity,
            time: alert.time,
            expires: alert.expires,
          ),
        )
        .toList(),
  );
}

const _sentinel = Object();
