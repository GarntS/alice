import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'alice_config.dart';
import 'rust_gen/bluetooth/prompt.dart';
import 'rust_gen/caldav/models.dart';
import 'rust_gen/state.dart';
import 'rust_gen/tray.dart';
import 'alice_platform.dart';
import 'panel_controller.dart';
import 'alice_theme.dart';
import 'notification_popup_state.dart';
import 'tray_menu_controller.dart';
import 'widgets/tray_menu_popup.dart';
import 'snapshot_state.dart';
import 'widgets/alice_icon.dart';
import 'widgets/notification_popups.dart';
import 'widgets/panels/panel_host.dart';
import 'widgets/panels/panel_sizes.dart';
import 'widgets/top_bar.dart';

// frb-generated bindings — used directly for watchPanelCommands.
import 'rust_gen/api.dart' as frb;

@visibleForTesting
bool applyPanelCommandToViewMap(
  Map<int, String> viewPanelMap,
  frb.PanelCommand? command, {
  int? expectedRequestId,
}) {
  if (command == null) {
    viewPanelMap.clear();
    return true;
  }
  if (expectedRequestId != null && command.requestId != expectedRequestId)
    return false;
  if (!command.visible) {
    viewPanelMap.remove(command.viewId);
  } else {
    viewPanelMap.clear();
    viewPanelMap[command.viewId] = command.panelId;
  }
  return true;
}

class AliceApp extends StatefulWidget {
  const AliceApp({super.key});

  @override
  State<AliceApp> createState() => _AliceAppState();
}

class _AliceAppState extends State<AliceApp> {
  late final AlicePlatform _platform = AlicePlatform();
  late final PanelController _panelController = PanelController();
  late final TrayMenuController _trayMenuController;
  late final StreamSubscription<BarSnapshot> _snapshotSubscription;
  late final StreamSubscription<frb.PanelCommand?> _panelCommandSubscription;
  late final StreamSubscription<frb.BarViewLifecycle> _barViewSubscription;

  AliceConfig _config = AliceConfig.fallback();
  late final AliceSnapshotState _snapshotState = AliceSnapshotState(
    config: _config,
  );
  late ThemeData _lightTheme = buildAliceTheme(_config, Brightness.light);
  late ThemeData _darkTheme = buildAliceTheme(_config, Brightness.dark);

  // viewId (int) → panelId (String) — populated when C++ calls alice_notify_panel_show
  final Map<int, String> _viewPanelMap = {};
  late final NotificationPopupState _notificationPopupState;
  int? _notificationPopupViewId;
  int _viewCount = 0;
  Set<int> _barViewIds = const {};

  @override
  void initState() {
    super.initState();
    _notificationPopupState = NotificationPopupState(config: _config);
    _notificationPopupState.addListener(_syncNotificationPopupState);
    _trayMenuController = TrayMenuController(_platform, _panelController);
    _panelController.addListener(_syncPanelState);
    _snapshotState.media.addListener(_syncMediaPanelSize);
    _snapshotState.trayOverflowCount.addListener(_syncTrayPanelSize);
    _snapshotState.bluetooth.addListener(_closeUnavailableBluetoothPanel);
    _loadConfig();

    _barViewSubscription = frb.watchBarViewLifecycle().listen((lifecycle) {
      if (mounted) {
        setState(
          () => _barViewIds = lifecycle.viewIds.map((id) => id.toInt()).toSet(),
        );
      }
    }, onError: (_, _) {});

    _panelCommandSubscription = frb.watchPanelCommands().listen((cmd) {
      if (!mounted) return;
      var applied = false;
      setState(
        () => applied = applyPanelCommandToViewMap(
          _viewPanelMap,
          cmd,
          expectedRequestId: _panelController.requestId,
        ),
      );
      if (applied && (cmd == null || !cmd.visible)) {
        _panelController.close();
      }
    }, onError: (_, _) {});

    _snapshotSubscription = _platform.watchBarSnapshots().listen((snapshot) {
      if (!mounted) return;
      _snapshotState.ingest(snapshot);
      _notificationPopupState.processSnapshot(snapshot.notifications);
    }, onError: (_, _) {});

    // Detect when C++ adds new FlViews (panel windows)
    _viewCount = WidgetsBinding.instance.platformDispatcher.views.length;
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged = () {
      final count = WidgetsBinding.instance.platformDispatcher.views.length;
      if (count != _viewCount) {
        if (mounted) setState(() => _viewCount = count);
      }
    };
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _platform.loadConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _lightTheme = buildAliceTheme(config, Brightness.light);
        _darkTheme = buildAliceTheme(config, Brightness.dark);
        _notificationPopupState.config = config;
        _snapshotState.updateConfig(config);
      });
    } catch (_) {}
  }

  Future<void> _syncPanelState() async {
    final requestId = _panelController.requestId;
    try {
      final openPanel = _panelController.openPanel;
      if (openPanel == null) {
        if (mounted) setState(_viewPanelMap.clear);
        await _platform.hidePanel(
          requestId: requestId,
          closedRequestId: _panelController.lastClosedRequestId,
        );
        return;
      }

      if (openPanel == AlicePanel.notifications) {
        _hideAllNotificationPopups();
      }

      final anchor = _panelController.anchor;
      if (anchor == null) return;

      final panelSize = openPanel == AlicePanel.trayMenu
          ? _trayMenuController.origin?.usableSize ?? alicePanelSize(openPanel)
          : alicePanelSize(openPanel);
      final panelId = openPanel.id;
      await _platform
          .showPanel(
            panelId,
            sourceViewId: anchor.sourceViewId,
            requestId: requestId,
            anchorX: anchor.globalPosition.dx,
            anchorY: anchor.globalPosition.dy,
            alignment: switch (anchor.alignment) {
              PanelAlignment.center => 'center',
              PanelAlignment.right => 'right',
            },
            width: panelSize.width,
            height: panelSize.height,
            includeTrayIconBytes: openPanel == AlicePanel.trayOverflow,
            panelTopGapPx: openPanel == AlicePanel.trayMenu
                ? 0
                : _config.panelTopGapPx,
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              throw TimeoutException('showPanel timed out for $panelId');
            },
          );
    } catch (error) {
      if (_panelController.requestId == requestId &&
          _panelController.openPanel == AlicePanel.trayMenu) {
        debugPrint('Tray menu surface failed: $error');
        _trayMenuController.close();
      }
    }
  }

  void _syncMediaPanelSize() {
    if (_panelController.openPanel == AlicePanel.media) _syncPanelState();
  }

  void _syncTrayPanelSize() {
    if (_panelController.openPanel == AlicePanel.trayOverflow)
      _syncPanelState();
  }

  Future<void> _closePanel() async {
    _panelController.close();
  }

  Future<void> _handlePowerAction(String action) async {
    try {
      await _platform.executePowerAction(action);
      _panelController.close();
    } catch (_) {}
  }

  Future<void> _handleMediaAction(String action) async {
    try {
      await _platform.sendMediaAction(action);
    } catch (_) {}
  }

  Future<void> _handleMediaSeek(int positionMicros) async {
    try {
      await _platform.seekMedia(positionMicros);
    } catch (_) {}
  }

  Future<void> _handleWorkspaceFocus(String label) async {
    try {
      await _platform.focusWorkspace(label);
    } catch (_) {}
  }

  Future<void> _handleTrayActivate(TrayItemSnapshot item) async {
    try {
      final outcome = await _platform.sendTrayAction(item, action: 'activate');
      if (outcome is TrayActionOutcome_Unsupported) {
        debugPrint(
          'Unsupported tray action destination=${item.serviceName} '
          'path=${item.objectPath} method=Activate',
        );
      } else if (outcome is TrayActionOutcome_Failed) {
        debugPrint(outcome.reason);
      }
    } catch (error) {
      // Diagnostic only: no toast or notification, and no duplicate Rust log.
      debugPrint('Tray activation failed: $error');
    }
  }

  void _closeUnavailableBluetoothPanel() {
    if (!_snapshotState.currentBluetooth.available &&
        _panelController.openPanel == AlicePanel.bluetooth) {
      _panelController.close();
    }
  }

  Future<void> _handleBluetoothScan() async {
    await _platform.requestBluetoothScan();
  }

  Future<void> _handleBluetoothConnect(String address) async {
    await _platform.connectBluetoothDevice(address);
  }

  Future<void> _handleBluetoothDisconnect(String address) async {
    await _platform.disconnectBluetoothDevice(address);
  }

  Future<void> _handleBluetoothPromptResponse(
    String token,
    PromptResponse response,
  ) async {
    await _platform.respondToBluetoothPrompt(token, response);
  }

  Future<void> _handleTaskRefresh() async {
    await _platform.requestCalDavRefresh();
  }

  Future<void> _handleTaskCompletion(
    TaskResourceIdentity identity,
    bool completed,
  ) => _platform.setCalDavTaskCompleted(identity, completed);

  Future<void> _handleDismissNotification(int id) async {
    try {
      await _platform.dismissNotification(id);
    } catch (_) {}
  }

  Future<void> _handleDismissAllNotifications() async {
    try {
      await _platform.dismissAllNotifications();
    } catch (_) {}
  }

  Future<void> _handleMarkNotificationRead(int id) async {
    try {
      await _platform.markNotificationRead(id);
    } catch (_) {}
  }

  Future<void> _handleMarkAllNotificationsRead() async {
    try {
      await _platform.markAllNotificationsRead(
        _snapshotState.currentNotifications,
      );
    } catch (_) {}
  }

  Future<void> _handleInvokeNotificationAction(int id, String actionKey) async {
    try {
      await _platform.invokeNotificationAction(id, actionKey);
    } catch (_) {}
  }

  void _hideAllNotificationPopups() {
    _notificationPopupState.hideAll();
  }

  void _syncNotificationPopupState() {
    if (!mounted) return;
    _snapshotState.updatePopupVisibleIds(_notificationPopupState.visibleIds);
    _syncNotificationPopupWindow();
  }

  Future<void> _syncNotificationPopupWindow() async {
    try {
      if (_notificationPopupState.visibleIds.isEmpty) {
        await _platform.hideNotificationPopups();
        return;
      }
      final viewId = await _platform.showNotificationPopups(
        panelTopGapPx: _config.panelTopGapPx,
      );
      if (mounted && viewId >= 0 && _notificationPopupViewId != viewId) {
        setState(() => _notificationPopupViewId = viewId);
      }
    } catch (_) {}
  }

  Future<void> _handleDismissPopupRead(int id) async {
    _notificationPopupState.remove(id);
    await _handleMarkNotificationRead(id);
  }

  Future<void> _handlePopupDismissNotification(int id) async {
    _notificationPopupState.remove(id);
    await _handleDismissNotification(id);
  }

  Future<void> _handlePopupAction(int id, String actionKey) async {
    _notificationPopupState.remove(id);
    await _handleInvokeNotificationAction(id, actionKey);
    await _handleMarkNotificationRead(id);
  }

  @override
  void dispose() {
    _barViewSubscription.cancel();
    _panelCommandSubscription.cancel();
    _snapshotSubscription.cancel();
    _notificationPopupState.removeListener(_syncNotificationPopupState);
    _notificationPopupState.dispose();
    _snapshotState.media.removeListener(_syncMediaPanelSize);
    _snapshotState.trayOverflowCount.removeListener(_syncTrayPanelSize);
    _snapshotState.bluetooth.removeListener(_closeUnavailableBluetoothPanel);
    _snapshotState.dispose();
    _trayMenuController.dispose();
    _panelController.removeListener(_syncPanelState);
    _panelController.dispose();
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged = null;
    super.dispose();
  }

  Widget _buildBar() {
    return MaterialApp(
      title: 'alice',
      debugShowCheckedModeBanner: false,
      themeMode: _config.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AliceIconTheme(
          config: _config,
          child: TopBar(
            config: _config,
            snapshotState: _snapshotState,
            panelController: _panelController,
            onWorkspaceTap: _handleWorkspaceFocus,
            onTrayItemTap: _handleTrayActivate,
            onTrayInput: _trayMenuController.handle,
            onBackgroundTap: _closePanel,
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(String? panelId) {
    final panel = panelId == null ? null : alicePanelFromId(panelId);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _config.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AliceIconTheme(
          config: _config,
          child: panel == AlicePanel.trayMenu
              ? TrayMenuPopup(controller: _trayMenuController)
              : Align(
                  alignment: Alignment.topRight,
                  child: panel == null
                      ? const SizedBox.shrink()
                      : AlicePanelCard(
                          panel: panel,
                          config: _config,
                          snapshotState: _snapshotState,
                          onPowerAction: _handlePowerAction,
                          onMediaAction: _handleMediaAction,
                          onSeekMedia: _handleMediaSeek,
                          onTrayAction: _handleTrayActivate,
                          onTrayInput: _trayMenuController.handle,
                          onDismissNotification: _handleDismissNotification,
                          onDismissAllNotifications:
                              _handleDismissAllNotifications,
                          onMarkAllNotificationsRead:
                              _handleMarkAllNotificationsRead,
                          onInvokeNotificationAction:
                              _handleInvokeNotificationAction,
                          onBluetoothScan: _handleBluetoothScan,
                          onBluetoothConnect: _handleBluetoothConnect,
                          onBluetoothDisconnect: _handleBluetoothDisconnect,
                          onBluetoothPromptResponse:
                              _handleBluetoothPromptResponse,
                          onTaskRefresh: _handleTaskRefresh,
                          onTaskCompletion: _handleTaskCompletion,
                        ),
                ),
        ),
      ),
    );
  }

  Widget _buildNotificationPopups() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _config.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AliceIconTheme(
          config: _config,
          child: ValueListenableBuilder<List<NotificationSnapshot>>(
            valueListenable: _snapshotState.popupNotifications,
            builder: (context, notifications, _) => NotificationPopupStack(
              notifications: notifications,
              onDismissPopupRead: _handleDismissPopupRead,
              onDismissNotification: _handlePopupDismissNotification,
              onMarkRead: _handleMarkNotificationRead,
              onInvokeAction: _handlePopupAction,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views.toList();
    return ViewCollection(
      views: views.map((v) {
        final child = _barViewIds.contains(v.viewId)
            ? _buildBar()
            : v.viewId == _notificationPopupViewId
            ? _buildNotificationPopups()
            : _viewPanelMap.containsKey(v.viewId)
            ? _buildPanel(_viewPanelMap[v.viewId])
            : const SizedBox.shrink();
        return View(view: v, child: child);
      }).toList(),
    );
  }
}
