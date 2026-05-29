import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AlicePanel { media, clock, trayOverflow, power, notifications }

AlicePanel? alicePanelFromId(String? panelId) {
  return switch (panelId) {
    'media' => AlicePanel.media,
    'clock' => AlicePanel.clock,
    'trayOverflow' => AlicePanel.trayOverflow,
    'power' => AlicePanel.power,
    'notifications' => AlicePanel.notifications,
    _ => null,
  };
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

  final ValueNotifier<bool> _mediaOpen = ValueNotifier(false);
  final ValueNotifier<bool> _clockOpen = ValueNotifier(false);
  final ValueNotifier<bool> _trayOverflowOpen = ValueNotifier(false);
  final ValueNotifier<bool> _notificationsOpen = ValueNotifier(false);
  final ValueNotifier<bool> _powerOpen = ValueNotifier(false);

  AlicePanel? get openPanel => _openPanel;
  PanelAnchor? get anchor => _anchor;

  ValueListenable<bool> get mediaOpen => _mediaOpen;
  ValueListenable<bool> get clockOpen => _clockOpen;
  ValueListenable<bool> get trayOverflowOpen => _trayOverflowOpen;
  ValueListenable<bool> get notificationsOpen => _notificationsOpen;
  ValueListenable<bool> get powerOpen => _powerOpen;

  ValueListenable<bool> openListenable(AlicePanel panel) {
    return switch (panel) {
      AlicePanel.media => _mediaOpen,
      AlicePanel.clock => _clockOpen,
      AlicePanel.trayOverflow => _trayOverflowOpen,
      AlicePanel.notifications => _notificationsOpen,
      AlicePanel.power => _powerOpen,
    };
  }

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
    final notifier = switch (panel) {
      AlicePanel.media => _mediaOpen,
      AlicePanel.clock => _clockOpen,
      AlicePanel.trayOverflow => _trayOverflowOpen,
      AlicePanel.notifications => _notificationsOpen,
      AlicePanel.power => _powerOpen,
    };
    if (notifier.value != value) notifier.value = value;
  }

  @override
  void dispose() {
    _mediaOpen.dispose();
    _clockOpen.dispose();
    _trayOverflowOpen.dispose();
    _notificationsOpen.dispose();
    _powerOpen.dispose();
    super.dispose();
  }
}
