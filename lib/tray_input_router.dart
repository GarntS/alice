import 'package:flutter/widgets.dart';

import 'panel_controller.dart';
import 'rust_gen/state.dart';
import 'rust_gen/tray.dart';

typedef TrayInputCallback =
    void Function(TrayItemSnapshot item, PanelAnchor anchor, bool secondary);

/// Shared routing policy for bar and overflow inputs; never binds middle-click.
bool _alwaysCurrent() => true;
void _diagnostic(String message) => debugPrint(message);

class TrayInputRouter {
  TrayInputRouter({
    required this.sendAction,
    required this.openMenu,
    this.diagnostic = _diagnostic,
    this.isCurrent = _alwaysCurrent,
  });

  final Future<TrayActionOutcome> Function(
    TrayItemSnapshot item,
    String method,
    Offset screenPosition,
  )
  sendAction;
  final Future<bool> Function(
    TrayItemSnapshot item,
    PanelAnchor anchor,
    Offset screenPosition,
  )
  openMenu;
  final void Function(String message) diagnostic;
  final bool Function() isCurrent;

  Future<void> route(
    TrayItemSnapshot item,
    PanelAnchor anchor,
    Offset screenPosition, {
    required bool secondary,
  }) async {
    try {
      if (!isCurrent()) return;
      if (!secondary && !item.itemIsMenu) {
        final outcome = await sendAction(item, 'activate', screenPosition);
        if (!isCurrent()) return;
        if (outcome is TrayActionOutcome_Executed) return;
        if (outcome is TrayActionOutcome_Failed) {
          diagnostic(outcome.reason);
          return; // Ambiguous failures never trigger another application action.
        }
      }
      var loaded = false;
      if (item.menuPath != null) {
        try {
          loaded = await openMenu(item, anchor, screenPosition);
        } catch (error) {
          diagnostic(
            'Tray menu load failed destination=${item.serviceName}: $error',
          );
        }
      }
      if (!isCurrent() || loaded) return;
      if (secondary && item.contextMenu == TrayCapability.supported) {
        final outcome = await sendAction(item, 'contextMenu', screenPosition);
        if (outcome is TrayActionOutcome_Failed) diagnostic(outcome.reason);
        if (outcome is TrayActionOutcome_Executed) return;
      }
      diagnostic(
        'No usable tray menu destination=${item.serviceName} path=${item.objectPath}',
      );
    } catch (error) {
      diagnostic('Tray action failed destination=${item.serviceName}: $error');
    }
  }
}
