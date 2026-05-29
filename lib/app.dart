import 'dart:async';

import 'package:flutter/material.dart';

import 'alice_config.dart';
import 'rust_gen/state.dart';
import 'alice_platform.dart';
import 'panel_controller.dart';
import 'alice_theme.dart';
import 'notification_popup_state.dart';
import 'widgets/notification_popups.dart';
import 'widgets/panels/panel_host.dart';
import 'widgets/panels/panel_spec.dart';
import 'widgets/top_bar.dart';

// frb-generated bindings — used directly for watchPanelCommands.
import 'rust_gen/api.dart' as frb;

class AliceApp extends StatefulWidget {
  const AliceApp({super.key});

  @override
  State<AliceApp> createState() => _AliceAppState();
}

class _AliceAppState extends State<AliceApp> {
  late final AlicePlatform _platform = AlicePlatform();
  late final PanelController _panelController = PanelController();
  late final StreamSubscription<BarSnapshot> _snapshotSubscription;
  late final StreamSubscription<frb.PanelCommand?> _panelCommandSubscription;

  AliceConfig _config = AliceConfig.fallback();
  late ThemeData _lightTheme = buildAliceTheme(_config, Brightness.light);
  late ThemeData _darkTheme = buildAliceTheme(_config, Brightness.dark);
  BarSnapshot _snapshot = const BarSnapshot(
    workspaces: [],
    media: null,
    memoryUsagePercent: 0,
    cpuUsageCores: 0,
    network: NetworkSnapshot(
      kind: NetworkKind.disconnected,
      label: 'Disconnected',
    ),
    clock: ClockSnapshot(
      timeZoneCode: 'UTC',
      dateLabel: '-- ---',
      timeLabel: '--:--',
    ),
    trayItems: [],
    notifications: [],
  );

  // viewId (int) → panelId (String) — populated when C++ calls alice_notify_panel_show
  final Map<int, String> _viewPanelMap = {};
  late final NotificationPopupState _notificationPopupState;
  int? _notificationPopupViewId;
  int _viewCount = 0;

  @override
  void initState() {
    super.initState();
    _notificationPopupState = NotificationPopupState(
      config: _config,
      onChanged: () {
        if (!mounted) return;
        setState(() {});
        _syncNotificationPopupWindow();
      },
    );
    _panelController.addListener(_syncPanelState);
    _loadConfig();

    _panelCommandSubscription = frb.watchPanelCommands().listen((cmd) {
      if (!mounted) return;
      if (cmd != null) {
        setState(() => _viewPanelMap[cmd.viewId] = cmd.panelId);
      } else {
        _panelController.close();
      }
    }, onError: (_, _) {});

    _snapshotSubscription = _platform.watchBarSnapshots().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _notificationPopupState.processSnapshot(snapshot.notifications);
      });
      _syncNotificationPopupWindow();
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
      });
    } catch (_) {}
  }

  Future<void> _syncPanelState() async {
    try {
      final openPanel = _panelController.openPanel;
      if (openPanel == null) {
        await _platform.hidePanel();
        return;
      }

      if (openPanel == AlicePanel.notifications) {
        _hideAllNotificationPopups();
      }

      final anchor = _panelController.anchor;
      if (anchor == null) return;

      final panelSize = alicePanelSize(
        openPanel,
        config: _config,
        snapshot: _snapshot,
        screenHeight: _screenHeight,
      );
      final panelId = _panelId(openPanel);
      await _platform
          .showPanel(
            panelId,
            anchorX: anchor.globalPosition.dx,
            anchorY: anchor.globalPosition.dy,
            alignment: switch (anchor.alignment) {
              PanelAlignment.center => 'center',
              PanelAlignment.right => 'right',
            },
            width: panelSize.width,
            height: panelSize.height,
            includeTrayIconBytes: openPanel == AlicePanel.trayOverflow,
            panelTopGapPx: _config.panelTopGapPx,
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              throw TimeoutException('showPanel timed out for $panelId');
            },
          );
    } catch (_) {}
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
      await _platform.sendTrayAction(item, action: 'activate');
    } catch (_) {}
  }

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
      await _platform.markAllNotificationsRead(_snapshot.notifications);
    } catch (_) {}
  }

  Future<void> _handleInvokeNotificationAction(int id, String actionKey) async {
    try {
      await _platform.invokeNotificationAction(id, actionKey);
    } catch (_) {}
  }

  void _hideAllNotificationPopups() {
    final changed = _notificationPopupState.hideAll();
    if (changed) setState(() {});
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
    setState(() => _notificationPopupState.remove(id));
    _syncNotificationPopupWindow();
    await _handleMarkNotificationRead(id);
  }

  Future<void> _handlePopupDismissNotification(int id) async {
    setState(() => _notificationPopupState.remove(id));
    _syncNotificationPopupWindow();
    await _handleDismissNotification(id);
  }

  Future<void> _handlePopupAction(int id, String actionKey) async {
    setState(() => _notificationPopupState.remove(id));
    _syncNotificationPopupWindow();
    await _handleInvokeNotificationAction(id, actionKey);
    await _handleMarkNotificationRead(id);
  }

  String _panelId(AlicePanel panel) {
    return switch (panel) {
      AlicePanel.media => 'media',
      AlicePanel.clock => 'clock',
      AlicePanel.trayOverflow => 'trayOverflow',
      AlicePanel.power => 'power',
      AlicePanel.notifications => 'notifications',
    };
  }

  double get _screenHeight {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return view.display.size.height;
    } catch (_) {
      return 1080;
    }
  }

  @override
  void dispose() {
    _panelCommandSubscription.cancel();
    _snapshotSubscription.cancel();
    _notificationPopupState.dispose();
    _panelController.removeListener(_syncPanelState);
    _panelController.dispose();
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged = null;
    super.dispose();
  }

  Widget _buildBar() {
    return AnimatedBuilder(
      animation: _panelController,
      builder: (context, _) {
        /*return MaterialApp(
          title: 'alice',
          debugShowCheckedModeBanner: false,
          themeMode: _config.themeMode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Align(
              alignment: Alignment.topCenter,
              child: TopBar(
                config: _config,
                snapshot: _snapshot,
                panelController: _panelController,
                onWorkspaceTap: _handleWorkspaceFocus,
                onTrayItemTap: _handleTrayActivate,
                onBackgroundTap: _closePanel,
              ),
            ),
          ),
        );*/
        return MaterialApp(
          title: 'alice',
          debugShowCheckedModeBanner: false,
          themeMode: _config.themeMode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: TopBar(
              config: _config,
              snapshot: _snapshot,
              panelController: _panelController,
              onWorkspaceTap: _handleWorkspaceFocus,
              onTrayItemTap: _handleTrayActivate,
              onBackgroundTap: _closePanel,
            ),
          ),
        );
      },
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
        body: Align(
          alignment: Alignment.topRight,
          child: panel == null
              ? const SizedBox.shrink()
              : AlicePanelCard(
                  panel: panel,
                  config: _config,
                  snapshot: _snapshot,
                  onPowerAction: _handlePowerAction,
                  onMediaAction: _handleMediaAction,
                  onSeekMedia: _handleMediaSeek,
                  onTrayAction: _handleTrayActivate,
                  onDismissNotification: _handleDismissNotification,
                  onDismissAllNotifications: _handleDismissAllNotifications,
                  onMarkAllNotificationsRead: _handleMarkAllNotificationsRead,
                  onInvokeNotificationAction: _handleInvokeNotificationAction,
                  screenHeight: _screenHeight,
                ),
        ),
      ),
    );
  }

  Widget _buildNotificationPopups() {
    final byId = {for (final n in _snapshot.notifications) n.id: n};
    final notifications = _notificationPopupState.visibleIds
        .map((id) => byId[id])
        .whereType<NotificationSnapshot>()
        .toList();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _config.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: NotificationPopupStack(
          notifications: notifications,
          onDismissPopupRead: _handleDismissPopupRead,
          onDismissNotification: _handlePopupDismissNotification,
          onMarkRead: _handleMarkNotificationRead,
          onInvokeAction: _handlePopupAction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views.toList();
    return ViewCollection(
      views: views.map((v) {
        final child = v.viewId == 0
            ? _buildBar()
            : v.viewId == _notificationPopupViewId
            ? _buildNotificationPopups()
            : _buildPanel(_viewPanelMap[v.viewId]);
        return View(view: v, child: child);
      }).toList(),
    );
  }
}
