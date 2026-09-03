import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'alice_config.dart';
import 'notification_popup_state.dart';
import 'rust_gen/caldav/models.dart';
import 'rust_gen/state.dart';

class AliceSnapshotState {
  AliceSnapshotState({
    AliceConfig? config,
    DateTime Function()? now,
    bool scheduleDateRollover = true,
  }) : _config = config ?? AliceConfig.fallback(),
       _now = now ?? DateTime.now {
    _recomputeTaskDateProjections();
    if (scheduleDateRollover) {
      _scheduleLocalDateRollover();
    }
  }

  AliceConfig _config;
  final DateTime Function() _now;
  Timer? _dateRolloverTimer;

  final ValueNotifier<List<WorkspaceSnapshot>> _workspaces = ValueNotifier(
    const [],
  );
  final ValueNotifier<MediaSnapshot?> _media = ValueNotifier(null);
  final ValueNotifier<double> _memoryUsagePercent = ValueNotifier(0);
  final ValueNotifier<double> _cpuUsageCores = ValueNotifier(0);
  final ValueNotifier<NetworkSnapshot> _network = ValueNotifier(
    const NetworkSnapshot(
      kind: NetworkKind.disconnected,
      label: 'Disconnected',
    ),
  );
  final ValueNotifier<ClockSnapshot> _clock = ValueNotifier(
    const ClockSnapshot(
      timeZoneCode: 'UTC',
      dateLabel: '-- ---',
      timeLabel: '--:--',
    ),
  );
  final ValueNotifier<WeatherSnapshot?> _weather = ValueNotifier(null);
  final ValueNotifier<BatterySnapshot?> _battery = ValueNotifier(null);
  final ValueNotifier<List<TrayItemSnapshot>> _trayItems = ValueNotifier(
    const [],
  );
  final ValueNotifier<List<NotificationSnapshot>> _notifications =
      ValueNotifier(const []);
  final ValueNotifier<List<NormalizedTask>> _tasks = ValueNotifier(const []);
  final ValueNotifier<CalDavSyncState> _caldavSyncState = ValueNotifier(
    const CalDavSyncState(
      freshness: CalDavFreshness.disabled,
      hasCachedData: false,
    ),
  );
  final ValueNotifier<int> _dueTodayTaskCount = ValueNotifier(0);
  final ValueNotifier<int> _overdueTaskCount = ValueNotifier(0);

  final ValueNotifier<List<TrayItemSnapshot>> _visibleTrayItems = ValueNotifier(
    const [],
  );
  final ValueNotifier<int> _trayOverflowCount = ValueNotifier(0);
  final ValueNotifier<int> _unreadNotificationCount = ValueNotifier(0);
  final ValueNotifier<List<NotificationSnapshot>> _popupNotifications =
      ValueNotifier(const []);

  List<int> _popupVisibleIds = const [];

  ValueListenable<List<WorkspaceSnapshot>> get workspaces => _workspaces;
  ValueListenable<MediaSnapshot?> get media => _media;
  ValueListenable<double> get memoryUsagePercent => _memoryUsagePercent;
  ValueListenable<double> get cpuUsageCores => _cpuUsageCores;
  ValueListenable<NetworkSnapshot> get network => _network;
  ValueListenable<ClockSnapshot> get clock => _clock;
  ValueListenable<WeatherSnapshot?> get weather => _weather;
  ValueListenable<BatterySnapshot?> get battery => _battery;
  ValueListenable<List<TrayItemSnapshot>> get trayItems => _trayItems;
  ValueListenable<List<NotificationSnapshot>> get notifications =>
      _notifications;
  ValueListenable<List<NormalizedTask>> get tasks => _tasks;
  ValueListenable<CalDavSyncState> get caldavSyncState => _caldavSyncState;
  ValueListenable<int> get dueTodayTaskCount => _dueTodayTaskCount;
  ValueListenable<int> get overdueTaskCount => _overdueTaskCount;
  ValueListenable<List<TrayItemSnapshot>> get visibleTrayItems =>
      _visibleTrayItems;
  ValueListenable<int> get trayOverflowCount => _trayOverflowCount;
  ValueListenable<int> get unreadNotificationCount => _unreadNotificationCount;
  ValueListenable<List<NotificationSnapshot>> get popupNotifications =>
      _popupNotifications;

  List<WorkspaceSnapshot> get currentWorkspaces => _workspaces.value;
  MediaSnapshot? get currentMedia => _media.value;
  double get currentMemoryUsagePercent => _memoryUsagePercent.value;
  double get currentCpuUsageCores => _cpuUsageCores.value;
  NetworkSnapshot get currentNetwork => _network.value;
  ClockSnapshot get currentClock => _clock.value;
  WeatherSnapshot? get currentWeather => _weather.value;
  BatterySnapshot? get currentBattery => _battery.value;
  List<TrayItemSnapshot> get currentTrayItems => _trayItems.value;
  List<NotificationSnapshot> get currentNotifications => _notifications.value;
  List<NormalizedTask> get currentTasks => _tasks.value;
  CalDavSyncState get currentCalDavSyncState => _caldavSyncState.value;
  int get currentDueTodayTaskCount => _dueTodayTaskCount.value;
  int get currentOverdueTaskCount => _overdueTaskCount.value;
  List<TrayItemSnapshot> get currentVisibleTrayItems => _visibleTrayItems.value;
  int get currentTrayOverflowCount => _trayOverflowCount.value;

  BarSnapshot get currentSnapshot => BarSnapshot(
    workspaces: currentWorkspaces,
    media: currentMedia,
    memoryUsagePercent: currentMemoryUsagePercent,
    cpuUsageCores: currentCpuUsageCores,
    network: currentNetwork,
    clock: currentClock,
    weather: currentWeather,
    battery: currentBattery,
    trayItems: currentTrayItems,
    notifications: currentNotifications,
    tasks: currentTasks,
    caldavSyncState: currentCalDavSyncState,
  );

  void ingest(BarSnapshot next) {
    if (!listEqualsBy(
      _workspaces.value,
      next.workspaces,
      workspaceSnapshotsEqual,
    )) {
      _workspaces.value = _freeze(next.workspaces);
    }
    if (!mediaSnapshotsEqual(_media.value, next.media)) {
      _media.value = next.media;
    }
    if (_memoryUsagePercent.value != next.memoryUsagePercent) {
      _memoryUsagePercent.value = next.memoryUsagePercent;
    }
    if (_cpuUsageCores.value != next.cpuUsageCores) {
      _cpuUsageCores.value = next.cpuUsageCores;
    }
    if (!networkSnapshotsEqual(_network.value, next.network)) {
      _network.value = next.network;
    }
    if (!clockSnapshotsEqual(_clock.value, next.clock)) {
      _clock.value = next.clock;
    }
    if (!weatherSnapshotsEqual(_weather.value, next.weather)) {
      _weather.value = next.weather;
    }
    if (!batterySnapshotsEqual(_battery.value, next.battery)) {
      _battery.value = next.battery;
    }
    if (!listEqualsBy(
      _trayItems.value,
      next.trayItems,
      trayItemSnapshotsEqual,
    )) {
      _trayItems.value = _freeze(next.trayItems);
      _recomputeTrayDerived();
    }
    if (!listEqualsBy(
      _notifications.value,
      next.notifications,
      notificationSnapshotsEqual,
    )) {
      _notifications.value = _freeze(next.notifications);
      _recomputeNotificationDerived();
    }
    if (!listEqualsBy(_tasks.value, next.tasks, normalizedTasksEqual)) {
      _tasks.value = _freeze(next.tasks);
      _recomputeTaskDateProjections();
    }
    if (!calDavSyncStatesEqual(_caldavSyncState.value, next.caldavSyncState)) {
      _caldavSyncState.value = next.caldavSyncState;
    }
  }

  @visibleForTesting
  void refreshTaskDateProjections() {
    _recomputeTaskDateProjections();
  }

  void _recomputeTaskDateProjections() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    var dueToday = 0;
    var overdue = 0;
    for (final task in _tasks.value) {
      if (task.status != TaskStatus.active || task.dueDate == null) continue;
      final due = DateTime.tryParse(task.dueDate!);
      if (due == null) continue;
      final date = DateTime(due.year, due.month, due.day);
      if (date == today) {
        dueToday++;
      } else if (date.isBefore(today)) {
        overdue++;
      }
    }
    if (_dueTodayTaskCount.value != dueToday) {
      _dueTodayTaskCount.value = dueToday;
    }
    if (_overdueTaskCount.value != overdue) {
      _overdueTaskCount.value = overdue;
    }
  }

  void _scheduleLocalDateRollover() {
    _dateRolloverTimer?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    final delay = nextDay.difference(now);
    _dateRolloverTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _recomputeTaskDateProjections();
      _scheduleLocalDateRollover();
    });
  }

  void updateConfig(AliceConfig config) {
    final oldMaxVisible = _config.maxVisibleTrayItems;
    final oldPopupConfig = _config.notifications;
    _config = config;
    if (oldMaxVisible != config.maxVisibleTrayItems) {
      _recomputeTrayDerived();
    }
    if (oldPopupConfig.showNotificationPopup !=
        config.notifications.showNotificationPopup) {
      _recomputeNotificationDerived();
    }
  }

  void updatePopupVisibleIds(Iterable<int> ids) {
    final next = List<int>.unmodifiable(ids);
    if (listEquals(_popupVisibleIds, next)) return;
    _popupVisibleIds = next;
    _recomputePopupNotifications();
  }

  void _recomputeTrayDerived() {
    final maxVisible = _config.maxVisibleTrayItems > 0
        ? _config.maxVisibleTrayItems - 1
        : 0;
    final visible = _freeze(_trayItems.value.take(maxVisible));
    final overflow = _trayItems.value.length - visible.length;
    if (!listEqualsBy(
      _visibleTrayItems.value,
      visible,
      trayItemSnapshotsEqual,
    )) {
      _visibleTrayItems.value = visible;
    }
    if (_trayOverflowCount.value != overflow) {
      _trayOverflowCount.value = overflow;
    }
  }

  void _recomputeNotificationDerived() {
    final unread = _notifications.value.where((n) => !n.isRead).length;
    if (_unreadNotificationCount.value != unread) {
      _unreadNotificationCount.value = unread;
    }
    _recomputePopupNotifications();
  }

  void _recomputePopupNotifications() {
    final byId = {for (final n in _notifications.value) n.id: n};
    final next = _config.notifications.showNotificationPopup
        ? _freeze(
            _popupVisibleIds
                .map((id) => byId[id])
                .whereType<NotificationSnapshot>(),
          )
        : const <NotificationSnapshot>[];
    if (!listEqualsBy(
      _popupNotifications.value,
      next,
      notificationSnapshotsEqual,
    )) {
      _popupNotifications.value = next;
    }
  }

  List<T> _freeze<T>(Iterable<T> values) =>
      UnmodifiableListView(values.toList(growable: false));

  void dispose() {
    _dateRolloverTimer?.cancel();
    _workspaces.dispose();
    _media.dispose();
    _memoryUsagePercent.dispose();
    _cpuUsageCores.dispose();
    _network.dispose();
    _clock.dispose();
    _weather.dispose();
    _battery.dispose();
    _trayItems.dispose();
    _notifications.dispose();
    _tasks.dispose();
    _caldavSyncState.dispose();
    _dueTodayTaskCount.dispose();
    _overdueTaskCount.dispose();
    _visibleTrayItems.dispose();
    _trayOverflowCount.dispose();
    _unreadNotificationCount.dispose();
    _popupNotifications.dispose();
  }
}

bool listEqualsBy<T>(List<T> a, List<T> b, bool Function(T a, T b) equals) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!equals(a[i], b[i])) return false;
  }
  return true;
}

bool workspaceSnapshotsEqual(WorkspaceSnapshot a, WorkspaceSnapshot b) =>
    a == b;

bool mediaSnapshotsEqual(MediaSnapshot? a, MediaSnapshot? b) => a == b;

bool networkSnapshotsEqual(NetworkSnapshot a, NetworkSnapshot b) => a == b;

bool clockSnapshotsEqual(ClockSnapshot a, ClockSnapshot b) => a == b;

bool batterySnapshotsEqual(BatterySnapshot? a, BatterySnapshot? b) => a == b;

bool weatherSnapshotsEqual(WeatherSnapshot? a, WeatherSnapshot? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.latitude == b.latitude &&
      a.longitude == b.longitude &&
      a.timezone == b.timezone &&
      a.offset == b.offset &&
      a.units == b.units &&
      a.lastUpdatedUnixSecs == b.lastUpdatedUnixSecs &&
      weatherPointsEqual(a.currently, b.currently) &&
      listEqualsBy(a.hourly, b.hourly, weatherPointsEqual) &&
      listEqualsBy(a.daily, b.daily, weatherDaysEqual) &&
      listEqualsBy(a.alerts, b.alerts, weatherAlertsEqual);
}

bool weatherPointsEqual(WeatherPoint a, WeatherPoint b) => a == b;

bool weatherDaysEqual(WeatherDay a, WeatherDay b) => a == b;

bool weatherAlertsEqual(WeatherAlert a, WeatherAlert b) => a == b;

bool trayItemSnapshotsEqual(TrayItemSnapshot a, TrayItemSnapshot b) =>
    a.id == b.id &&
    a.label == b.label &&
    a.serviceName == b.serviceName &&
    a.objectPath == b.objectPath &&
    bytesEqual(a.iconPngBytes, b.iconPngBytes);

bool normalizedTasksEqual(NormalizedTask a, NormalizedTask b) =>
    a.identity.collectionHref == b.identity.collectionHref &&
    a.identity.resourceHref == b.identity.resourceHref &&
    a.uid == b.uid &&
    a.title == b.title &&
    a.collectionName == b.collectionName &&
    a.dueDate == b.dueDate &&
    a.completedAtUnixSecs == b.completedAtUnixSecs &&
    a.status == b.status &&
    a.priority == b.priority;

bool calDavSyncStatesEqual(CalDavSyncState a, CalDavSyncState b) =>
    a.freshness == b.freshness &&
    a.lastSuccessUnixSecs == b.lastSuccessUnixSecs &&
    a.error == b.error &&
    a.hasCachedData == b.hasCachedData;

bool notificationActionSnapshotsEqual(
  NotificationActionSnapshot a,
  NotificationActionSnapshot b,
) => a == b;

bool notificationSnapshotsEqual(
  NotificationSnapshot a,
  NotificationSnapshot b,
) =>
    a.id == b.id &&
    a.appName == b.appName &&
    a.appIcon == b.appIcon &&
    a.summary == b.summary &&
    a.body == b.body &&
    a.urgency == b.urgency &&
    listEqualsBy(a.actions, b.actions, notificationActionSnapshotsEqual) &&
    a.category == b.category &&
    a.isRead == b.isRead &&
    a.receivedAtUnixSecs == b.receivedAtUnixSecs &&
    bytesEqual(a.imageData, b.imageData) &&
    a.imagePath == b.imagePath;

bool bytesEqual(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String notificationContentSignature(NotificationSnapshot n) =>
    notificationSignature(n);
