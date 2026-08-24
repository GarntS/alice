import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

enum AlicePanel {
  media('media'),
  clock('clock'),
  tasks('tasks'),
  weather('weather'),
  trayOverflow('trayOverflow'),
  power('power'),
  notifications('notifications');

  const AlicePanel(this.id);

  final String id;
}

AlicePanel? alicePanelFromId(String? panelId) {
  for (final panel in AlicePanel.values) {
    if (panel.id == panelId) return panel;
  }
  return null;
}

enum PanelAlignment { center, right }

class PanelAnchor {
  const PanelAnchor({required this.globalPosition, required this.alignment});

  final Offset globalPosition;
  final PanelAlignment alignment;
}

class PanelController extends ChangeNotifier {
  AlicePanel? _openPanel;
  PanelAnchor? _anchor;

  final Map<AlicePanel, ValueNotifier<bool>> _openNotifiers = {
    for (final panel in AlicePanel.values) panel: ValueNotifier(false),
  };

  AlicePanel? get openPanel => _openPanel;
  PanelAnchor? get anchor => _anchor;

  ValueListenable<bool> get mediaOpen => openListenable(AlicePanel.media);
  ValueListenable<bool> get clockOpen => openListenable(AlicePanel.clock);
  ValueListenable<bool> get tasksOpen => openListenable(AlicePanel.tasks);
  ValueListenable<bool> get weatherOpen => openListenable(AlicePanel.weather);
  ValueListenable<bool> get trayOverflowOpen =>
      openListenable(AlicePanel.trayOverflow);
  ValueListenable<bool> get notificationsOpen =>
      openListenable(AlicePanel.notifications);
  ValueListenable<bool> get powerOpen => openListenable(AlicePanel.power);

  ValueListenable<bool> openListenable(AlicePanel panel) =>
      _openNotifiers[panel]!;

  bool isOpen(AlicePanel panel) => _openPanel == panel;

  void toggle(AlicePanel panel, PanelAnchor anchor) {
    final previous = _openPanel;
    if (_openPanel == panel) {
      _openPanel = null;
      _anchor = null;
    } else {
      _openPanel = panel;
      _anchor = anchor;
    }
    _notifyGranular(previous, _openPanel);
    notifyListeners();
  }

  void close() {
    if (_openPanel == null) {
      return;
    }

    final previous = _openPanel;
    _openPanel = null;
    _anchor = null;
    _notifyGranular(previous, null);
    notifyListeners();
  }

  void _notifyGranular(AlicePanel? previous, AlicePanel? next) {
    if (previous == next) return;
    if (previous != null) _setOpen(previous, false);
    if (next != null) _setOpen(next, true);
  }

  void _setOpen(AlicePanel panel, bool value) {
    final notifier = _openNotifiers[panel]!;
    if (notifier.value != value) notifier.value = value;
  }

  @override
  void dispose() {
    for (final notifier in _openNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }
}
