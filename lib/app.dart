import 'dart:async';

import 'package:flutter/material.dart';

import 'alice_config.dart';
import 'rust_gen/state.dart';
import 'alice_platform.dart';
import 'panel_controller.dart';
import 'alice_theme.dart';
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
  );

  // viewId (int) → panelId (String) — populated when C++ calls alice_notify_panel_show
  final Map<int, String> _viewPanelMap = {};
  int _viewCount = 0;

  @override
  void initState() {
    super.initState();
    _panelController.addListener(_syncPanelState);
    _loadConfig();

    _panelCommandSubscription = frb.watchPanelCommands().listen(
      (cmd) {
        if (!mounted) return;
        if (cmd != null) {
          setState(() => _viewPanelMap[cmd.viewId] = cmd.panelId);
        } else {
          _panelController.close();
        }
      },
      onError: (Object e, StackTrace st) =>
          debugPrint('Failed to receive panel command: $e'),
    );

    _snapshotSubscription = _platform.watchBarSnapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() => _snapshot = snapshot);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Failed to receive native snapshots: $error');
      },
    );

    // Detect when C++ adds new FlViews (panel windows)
    _viewCount =
        WidgetsBinding.instance.platformDispatcher.views.length;
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged = () {
      final count =
          WidgetsBinding.instance.platformDispatcher.views.length;
      if (count != _viewCount) {
        if (mounted) setState(() => _viewCount = count);
      }
    };
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _platform.loadConfig();
      if (!mounted) return;
      setState(() => _config = config);
    } catch (error) {
      debugPrint('Failed to load native config, using fallback: $error');
    }
  }

  Future<void> _syncPanelState() async {
    try {
      final openPanel = _panelController.openPanel;
      if (openPanel == null) {
        await _platform.hidePanel();
        return;
      }

      final anchor = _panelController.anchor;
      if (anchor == null) return;

      final panelSize = alicePanelSize(
        openPanel,
        config: _config,
        snapshot: _snapshot,
      );

      await _platform.showPanel(
        _panelId(openPanel),
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
      );
    } catch (error) {
      debugPrint('Failed to sync panel state: $error');
    }
  }

  Future<void> _closePanel() async {
    _panelController.close();
  }

  Future<void> _handlePowerAction(String action) async {
    try {
      await _platform.executePowerAction(action);
      _panelController.close();
    } catch (error) {
      debugPrint('Failed to execute power action: $error');
    }
  }

  Future<void> _handleMediaAction(String action) async {
    try {
      await _platform.sendMediaAction(action);
    } catch (error) {
      debugPrint('Failed to send media action: $error');
    }
  }

  Future<void> _handleMediaSeek(int positionMicros) async {
    try {
      await _platform.seekMedia(positionMicros);
    } catch (error) {
      debugPrint('Failed to seek media: $error');
    }
  }

  Future<void> _handleWorkspaceFocus(String label) async {
    try {
      await _platform.focusWorkspace(label);
    } catch (error) {
      debugPrint('Failed to focus workspace: $error');
    }
  }

  Future<void> _handleTrayActivate(TrayItemSnapshot item) async {
    try {
      await _platform.sendTrayAction(item, action: 'activate');
    } catch (error) {
      debugPrint('Failed to activate tray item: $error');
    }
  }

  String _panelId(AlicePanel panel) {
    return switch (panel) {
      AlicePanel.media => 'media',
      AlicePanel.clock => 'clock',
      AlicePanel.trayOverflow => 'trayOverflow',
      AlicePanel.power => 'power',
    };
  }

  @override
  void dispose() {
    _panelCommandSubscription.cancel();
    _snapshotSubscription.cancel();
    _panelController.removeListener(_syncPanelState);
    _panelController.dispose();
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged = null;
    super.dispose();
  }

  Widget _buildBar() {
    return AnimatedBuilder(
      animation: _panelController,
      builder: (context, _) {
        return MaterialApp(
          title: 'alice',
          debugShowCheckedModeBanner: false,
          themeMode: _config.themeMode,
          theme: buildAliceTheme(_config, Brightness.light),
          darkTheme: buildAliceTheme(_config, Brightness.dark),
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
        );
      },
    );
  }

  Widget _buildPanel(String? panelId) {
    final panel = panelId == null ? null : alicePanelFromId(panelId);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _config.themeMode,
      theme: buildAliceTheme(_config, Brightness.light),
      darkTheme: buildAliceTheme(_config, Brightness.dark),
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
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final views =
        WidgetsBinding.instance.platformDispatcher.views.toList();
    return ViewCollection(
      views: views.map((v) {
        final child = v.viewId == 0
            ? _buildBar()
            : _buildPanel(_viewPanelMap[v.viewId]);
        return View(view: v, child: child);
      }).toList(),
    );
  }
}
