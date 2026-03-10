import 'package:flutter/material.dart';

enum AlicePanel { media, clock, trayOverflow, power }

enum PanelAlignment { center, right }

class PanelAnchor {
  const PanelAnchor({required this.globalPosition, required this.alignment});

  final Offset globalPosition;
  final PanelAlignment alignment;
}

class PanelController extends ChangeNotifier {
  AlicePanel? _openPanel;
  PanelAnchor? _anchor;

  AlicePanel? get openPanel => _openPanel;
  PanelAnchor? get anchor => _anchor;

  bool isOpen(AlicePanel panel) => _openPanel == panel;

  void toggle(AlicePanel panel, PanelAnchor anchor) {
    if (_openPanel == panel) {
      _openPanel = null;
      _anchor = null;
    } else {
      _openPanel = panel;
      _anchor = anchor;
    }
    notifyListeners();
  }

  void close() {
    if (_openPanel == null) {
      return;
    }

    _openPanel = null;
    _anchor = null;
    notifyListeners();
  }
}
