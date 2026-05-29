import 'dart:async';

import 'alice_config.dart';
import 'rust_gen/state.dart';

class NotificationPopupState {
  NotificationPopupState({required this.config, this.onChanged});

  AliceConfig config;
  final void Function()? onChanged;

  final Map<int, String> _seenSignatures = {};
  final List<int> _visibleIds = [];
  final Map<int, Timer> _timers = {};

  List<int> get visibleIds => List.unmodifiable(_visibleIds);

  bool processSnapshot(List<NotificationSnapshot> notifications) {
    var changed = false;
    final current = {for (final n in notifications) n.id: n};
    _visibleIds.removeWhere((id) {
      final stale = !current.containsKey(id);
      if (stale) {
        _cancelTimer(id);
        changed = true;
      }
      return stale;
    });

    for (final n in notifications) {
      final signature = notificationSignature(n);
      final previous = _seenSignatures[n.id];
      if (previous != null && previous != signature) {
        changed = _enqueue(n) || changed;
      } else if (previous == null &&
          config.notifications.showNotificationPopup) {
        changed = _enqueue(n) || changed;
      }
      _seenSignatures[n.id] = signature;
    }
    _seenSignatures.removeWhere((id, _) => !current.containsKey(id));
    return changed;
  }

  bool remove(int id) {
    final removed = _visibleIds.remove(id);
    _cancelTimer(id);
    return removed;
  }

  bool hideAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (_visibleIds.isEmpty) return false;
    _visibleIds.clear();
    return true;
  }

  void dispose() {
    hideAll();
  }

  bool _enqueue(NotificationSnapshot notification) {
    if (!config.notifications.showNotificationPopup) return false;
    var changed = _visibleIds.remove(notification.id);
    _visibleIds.add(notification.id);
    changed = true;
    while (_visibleIds.length > 4) {
      final bumped = _visibleIds.removeAt(0);
      _cancelTimer(bumped);
    }
    _startTimer(notification);
    return changed;
  }

  void _startTimer(NotificationSnapshot notification) {
    _cancelTimer(notification.id);
    final displayMs = config.notifications.notificationDisplayTimeMs;
    if (displayMs == 0) return;
    if (notification.urgency == NotificationUrgency.critical &&
        !config.notifications.expireCriticalNotifications) {
      return;
    }
    _timers[notification.id] = Timer(Duration(milliseconds: displayMs), () {
      remove(notification.id);
      onChanged?.call();
    });
  }

  void _cancelTimer(int id) {
    _timers.remove(id)?.cancel();
  }
}

String notificationSignature(NotificationSnapshot n) {
  return [
    n.appName,
    n.appIcon,
    n.summary,
    n.body,
    n.imagePath ?? '',
    n.receivedAtUnixSecs.toString(),
    n.urgency.name,
    n.actions.map((a) => '${a.key}:${a.label}').join('|'),
  ].join('\u0001');
}
