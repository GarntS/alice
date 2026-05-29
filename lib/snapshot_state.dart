import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'alice_config.dart';
import 'notification_popup_state.dart';
import 'rust_gen/state.dart';

class AliceSnapshotState {
  AliceSnapshotState({AliceConfig? config})
    : _config = config ?? AliceConfig.fallback();

  AliceConfig _config;

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
  final ValueNotifier<List<TrayItemSnapshot>> _trayItems = ValueNotifier(
    const [],
  );
  final ValueNotifier<List<NotificationSnapshot>> _notifications =
      ValueNotifier(const []);

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
  ValueListenable<List<TrayItemSnapshot>> get trayItems => _trayItems;
  ValueListenable<List<NotificationSnapshot>> get notifications =>
      _notifications;
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
  List<TrayItemSnapshot> get currentTrayItems => _trayItems.value;
  List<NotificationSnapshot> get currentNotifications => _notifications.value;
  List<TrayItemSnapshot> get currentVisibleTrayItems => _visibleTrayItems.value;
  int get currentTrayOverflowCount => _trayOverflowCount.value;

  BarSnapshot get currentSnapshot => BarSnapshot(
    workspaces: currentWorkspaces,
    media: currentMedia,
    memoryUsagePercent: currentMemoryUsagePercent,
    cpuUsageCores: currentCpuUsageCores,
    network: currentNetwork,
    clock: currentClock,
    trayItems: currentTrayItems,
    notifications: currentNotifications,
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
    final next = _freeze(
      _popupVisibleIds.map((id) => byId[id]).whereType<NotificationSnapshot>(),
    );
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
    _workspaces.dispose();
    _media.dispose();
    _memoryUsagePercent.dispose();
    _cpuUsageCores.dispose();
    _network.dispose();
    _clock.dispose();
    _trayItems.dispose();
    _notifications.dispose();
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
    a.label == b.label &&
    a.isFocused == b.isFocused &&
    a.isVisible == b.isVisible;

bool mediaSnapshotsEqual(MediaSnapshot? a, MediaSnapshot? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.title == b.title &&
      a.artist == b.artist &&
      a.albumTitle == b.albumTitle &&
      a.artUrl == b.artUrl &&
      a.positionLabel == b.positionLabel &&
      a.lengthLabel == b.lengthLabel &&
      a.positionMicros == b.positionMicros &&
      a.lengthMicros == b.lengthMicros &&
      a.isPlaying == b.isPlaying;
}

bool networkSnapshotsEqual(NetworkSnapshot a, NetworkSnapshot b) =>
    a.kind == b.kind && a.label == b.label;

bool clockSnapshotsEqual(ClockSnapshot a, ClockSnapshot b) =>
    a.timeZoneCode == b.timeZoneCode &&
    a.dateLabel == b.dateLabel &&
    a.timeLabel == b.timeLabel;

bool trayItemSnapshotsEqual(TrayItemSnapshot a, TrayItemSnapshot b) =>
    a.id == b.id &&
    a.label == b.label &&
    a.serviceName == b.serviceName &&
    a.objectPath == b.objectPath &&
    bytesEqual(a.iconPngBytes, b.iconPngBytes);

bool notificationActionSnapshotsEqual(
  NotificationActionSnapshot a,
  NotificationActionSnapshot b,
) => a.key == b.key && a.label == b.label;

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
