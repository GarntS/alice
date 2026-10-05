import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'alice_platform.dart';
import 'panel_controller.dart';
import 'rust_gen/state.dart';
import 'rust_gen/tray.dart';
import 'rust_gen/tray_menu_service.dart';
import 'tray_anchor.dart';
import 'tray_input_router.dart';

/// Coordinates pending loads, live updates, and the existing single-popup policy.
class TrayMenuController extends ChangeNotifier {
  TrayMenuController(this.platform, this.panels) {
    panels.addListener(_panelChanged);
  }
  final AlicePlatform platform;
  final PanelController panels;
  TrayMenuSnapshot? snapshot;
  TrayResolvedAnchor? origin;
  BigInt? _request;
  Timer? _timer;
  int _generation = 0;
  bool _changingPanel = false;
  bool _refreshing = false;
  bool selecting = false;
  bool _disposed = false;

  void _panelChanged() {
    if (!_changingPanel && panels.openPanel != AlicePanel.trayMenu)
      close(closePanel: false);
  }

  void _changePanel(VoidCallback change) {
    _changingPanel = true;
    try {
      change();
    } finally {
      _changingPanel = false;
    }
  }

  void close({bool closePanel = true}) {
    _generation++;
    final request = _request;
    _request = null;
    _timer?.cancel();
    _timer = null;
    snapshot = null;
    origin = null;
    selecting = false;
    if (request != null)
      unawaited(
        platform.cancelTrayMenu(request).catchError((Object error) {
          debugPrint('Tray menu cancellation failed: $error');
        }),
      );
    if (closePanel && panels.openPanel == AlicePanel.trayMenu)
      _changePanel(panels.close);
    if (!_disposed) notifyListeners();
  }

  Future<void> handle(
    TrayItemSnapshot item,
    PanelAnchor anchor,
    bool secondary,
  ) async {
    close();
    final generation = _generation;
    try {
      // Resolve a panel-relative origin while overflow still exists. It cannot
      // be reconstructed from a disposed Flutter view after closure.
      final resolved = await platform.resolveTrayAnchor(anchor);
      if (_disposed || generation != _generation) return;
      origin = resolved;
      _changePanel(panels.close);
      final router = TrayInputRouter(
        isCurrent: () => !_disposed && generation == _generation,
        sendAction: (item, method, point) => platform.sendTrayAction(
          item,
          action: method,
          x: point.dx.round(),
          y: point.dy.round(),
        ),
        openMenu: (item, anchor, point) async {
          final request = await platform.beginTrayMenuRequest();
          if (_disposed || generation != _generation) {
            await platform.cancelTrayMenu(request);
            return true;
          }
          _request = request;
          try {
            final loaded = await platform.loadTrayMenu(request, item);
            if (_disposed || generation != _generation || _request != request) {
              await platform.cancelTrayMenu(request);
              return true;
            }
            snapshot = loaded;
            notifyListeners();
            _changePanel(
              () => panels.toggle(AlicePanel.trayMenu, resolved.anchor),
            );
            _timer = Timer.periodic(
              const Duration(milliseconds: 150),
              (_) => _refresh(request),
            );
            return true;
          } catch (_) {
            if (_request == request) _request = null;
            await platform.cancelTrayMenu(request);
            rethrow;
          }
        },
      );
      await router.route(
        item,
        resolved.anchor,
        resolved.screenPosition,
        secondary: secondary,
      );
    } catch (error) {
      debugPrint('Tray input failed destination=${item.serviceName}: $error');
      if (generation == _generation) close();
    }
  }

  Future<void> _refresh(BigInt request, {int? submenuId}) async {
    if (_disposed || _refreshing || _request != request || selecting) return;
    _refreshing = true;
    try {
      final update = await platform.refreshTrayMenu(
        request,
        submenuId: submenuId,
      );
      if (_disposed || _request != request) return;
      if (update is TrayMenuUpdate_Closed) {
        close();
      }
      if (update is TrayMenuUpdate_Updated) {
        snapshot = update.snapshot;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Tray menu refresh failed: $error');
      if (_request == request) close();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> prepareSubmenu(int id) async {
    final request = _request;
    if (request != null) await _refresh(request, submenuId: id);
  }

  Future<void> select(TrayMenuSelection selection) async {
    final request = _request;
    final captured = origin;
    if (request == null || captured == null || selecting) return;
    selecting = true;
    notifyListeners();
    try {
      final outcome = await platform.selectTrayMenu(
        request,
        selection,
        x: captured.screenPosition.dx.round(),
        y: captured.screenPosition.dy.round(),
        timestamp: DateTime.now().millisecondsSinceEpoch & 0xffffffff,
      );
      if (outcome is TrayActionOutcome_Failed) debugPrint(outcome.reason);
      if (outcome is TrayActionOutcome_Unsupported)
        debugPrint('Unsupported tray menu action');
    } catch (error) {
      debugPrint('Tray menu selection failed: $error');
    } finally {
      if (_request == request) close();
    }
  }

  @override
  void dispose() {
    panels.removeListener(_panelChanged);
    _disposed = true;
    close();
    super.dispose();
  }
}
