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

enum AliceSurfaceMode { bar, panel }

class AliceApp extends StatefulWidget {
  const AliceApp({super.key, required this.surfaceMode});

  factory AliceApp.fromArguments(List<String> args) {
    String? windowKind;
    for (final arg in args) {
      if (arg.startsWith('--alice-window=')) {
        windowKind = arg.substring('--alice-window='.length);
      }
    }

    if (windowKind == 'panel') {
      return const AliceApp(surfaceMode: AliceSurfaceMode.panel);
    }

    return const AliceApp(surfaceMode: AliceSurfaceMode.bar);
  }

  final AliceSurfaceMode surfaceMode;

  @override
  State<AliceApp> createState() => _AliceAppState();
}

class _AliceAppState extends State<AliceApp> {
  late final AlicePlatform _platform = AlicePlatform();
  late final PanelController _panelController = PanelController();
  late final StreamSubscription<BarSnapshot> _snapshotSubscription;
  late final StreamSubscription<AlicePanel?> _panelTypeSubscription;

  AliceConfig _config = AliceConfig.fallback();
  AlicePanel? _activePanel;
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

  @override
  void initState() {
    super.initState();
    _panelController.addListener(_syncPanelState);
    _loadConfig();
    _panelTypeSubscription = _platform.watchPanelType().listen(
      (panel) {
        if (mounted) setState(() => _activePanel = panel);
      },
      onError: (Object e, StackTrace st) =>
          debugPrint('Failed to receive panel type: $e'),
    );
    _snapshotSubscription = _platform.watchBarSnapshots().listen(
      (snapshot) {
        if (!mounted) {
          return;
        }
        setState(() {
          _snapshot = snapshot;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Failed to receive native snapshots: $error');
      },
    );
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _platform.loadConfig();
      if (!mounted) {
        return;
      }
      setState(() {
        _config = config;
      });
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
      if (anchor == null) {
        return;
      }
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
      );
    } catch (error) {
      debugPrint('Failed to sync panel state: $error');
    }
  }

  Future<void> _closePanel() async {
    if (widget.surfaceMode == AliceSurfaceMode.panel) {
      await _platform.hidePanel();
      return;
    }

    _panelController.close();
  }

  Future<void> _handlePowerAction(String action) async {
    try {
      await _platform.executePowerAction(action);
      await _closePanel();
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
    _panelTypeSubscription.cancel();
    _snapshotSubscription.cancel();
    _panelController.removeListener(_syncPanelState);
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            body: widget.surfaceMode == AliceSurfaceMode.bar
                ? Align(
                    alignment: Alignment.topCenter,
                    child: TopBar(
                      config: _config,
                      snapshot: _snapshot,
                      panelController: _panelController,
                      onWorkspaceTap: _handleWorkspaceFocus,
                      onTrayItemTap: _handleTrayActivate,
                      onBackgroundTap: () {
                        _closePanel();
                      },
                    ),
                  )
                : Align(
                    alignment: Alignment.topRight,
                    child: _activePanel == null
                        ? const SizedBox.shrink()
                        : AlicePanelCard(
                            panel: _activePanel!,
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
      },
    );
  }
}
