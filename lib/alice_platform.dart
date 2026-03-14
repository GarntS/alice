import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter/services.dart';

import 'alice_config.dart';
import 'rust_gen/state.dart';
import 'panel_controller.dart';

// frb-generated bindings.
import 'rust_gen/api.dart' as frb;
// config.dart defines frb.ThemeMode which shadows Flutter's ThemeMode;
// aliased to avoid the conflict.
import 'rust_gen/config.dart' as frb_config;
export 'rust_gen/frb_generated.dart' show RustLib;

const _methodChannelName = 'alice/platform';

/// Platform adapter backed by flutter_rust_bridge for data operations and the
/// existing method channel for the two GTK layer-shell commands (showPanel /
/// hidePanel) that still live in C++.
class AlicePlatform {
  AlicePlatform({MethodChannel? methodChannel})
      : _methodChannel =
            methodChannel ?? const MethodChannel(_methodChannelName);

  final MethodChannel _methodChannel;
  final Map<String, Uint8List> _trayIconCache = <String, Uint8List>{};

  // ---------------------------------------------------------------------------
  // Streaming APIs
  // ---------------------------------------------------------------------------

  Stream<BarSnapshot> watchBarSnapshots() {
    return frb.watchBarSnapshots().map(_stabiliseIcons);
  }

  Stream<AlicePanel?> watchPanelType() {
    return frb.watchPanelCommands().map(
      (cmd) => cmd == null ? null : alicePanelFromId(cmd.panelId),
    );
  }

  // ---------------------------------------------------------------------------
  // One-shot calls (frb)
  // ---------------------------------------------------------------------------

  Future<AliceConfig> loadConfig() async {
    return _mapConfig(await frb.loadConfig());
  }

  Future<void> sendMediaAction(String action) {
    return frb.sendMediaAction(action: action);
  }

  Future<void> seekMedia(int positionMicros) {
    return frb.seekMedia(positionMicros: positionMicros);
  }

  Future<void> focusWorkspace(String label) {
    return frb.focusWorkspace(label: label);
  }

  Future<void> sendTrayAction(
    TrayItemSnapshot item, {
    required String action,
    int x = 0,
    int y = 0,
  }) {
    return frb.sendTrayAction(
      serviceName: item.serviceName,
      objectPath: item.objectPath,
      action: action,
      x: x,
      y: y,
    );
  }

  Future<void> executePowerAction(String action) {
    return frb.executePowerAction(action: action);
  }

  // ---------------------------------------------------------------------------
  // Panel geometry commands — handled by C++ GTK layer-shell code
  // ---------------------------------------------------------------------------

  Future<void> showPanel(
    String panelId, {
    required double anchorX,
    required double anchorY,
    required String alignment,
    required double width,
    required double height,
    required bool includeTrayIconBytes,
  }) {
    return _methodChannel.invokeMethod<void>('showPanel', <String, Object?>{
      'panelId': panelId,
      'anchorX': anchorX,
      'anchorY': anchorY,
      'alignment': alignment,
      'width': width,
      'height': height,
      'includeTrayIconBytes': includeTrayIconBytes,
    });
  }

  Future<void> hidePanel() {
    return _methodChannel.invokeMethod<void>('hidePanel');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Rewrites tray icon bytes in each snapshot with stable (cached) references
  /// so that identical PNG data doesn't trigger unnecessary widget rebuilds.
  BarSnapshot _stabiliseIcons(BarSnapshot snapshot) {
    final activeTrayKeys = <String>{};
    final stableItems = snapshot.trayItems.map((item) {
      final key = '${item.serviceName}|${item.objectPath}';
      activeTrayKeys.add(key);
      final stableBytes = _stableTrayIconBytes(key, item.iconPngBytes);
      if (identical(stableBytes, item.iconPngBytes)) return item;
      return TrayItemSnapshot(
        id: item.id,
        label: item.label,
        serviceName: item.serviceName,
        objectPath: item.objectPath,
        iconPngBytes: stableBytes,
      );
    }).toList();
    _trayIconCache.removeWhere((key, _) => !activeTrayKeys.contains(key));

    if (identical(stableItems, snapshot.trayItems)) return snapshot;
    return BarSnapshot(
      workspaces: snapshot.workspaces,
      media: snapshot.media,
      memoryUsagePercent: snapshot.memoryUsagePercent,
      cpuUsageCores: snapshot.cpuUsageCores,
      network: snapshot.network,
      clock: snapshot.clock,
      trayItems: stableItems,
    );
  }

  AliceConfig _mapConfig(frb_config.AliceConfig r) {
    return AliceConfig(
      themeMode: switch (r.themeMode) {
        frb_config.ThemeMode.light => ThemeMode.light,
        frb_config.ThemeMode.dark => ThemeMode.dark,
        frb_config.ThemeMode.system => ThemeMode.system,
      },
      accentColor: _colorFromHex(r.accentColor),
      showNetworkLabel: r.showNetworkLabel,
      maxVisibleTrayItems: r.maxVisibleTrayItems,
      localTimeZoneLabel: r.localTimeZoneLabel,
      timeZones: r.timeZones
          .map((tz) => TimeZoneConfig(label: tz.label, offsetHours: tz.offsetHours))
          .toList(),
      powerCommands: PowerCommandConfig(
        lock: r.powerCommands.lock,
        lockAndSuspend: r.powerCommands.lockAndSuspend,
        restart: r.powerCommands.restart,
        poweroff: r.powerCommands.poweroff,
      ),
    );
  }

  Color _colorFromHex(String value) {
    final normalized = value.replaceFirst('#', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final colorValue = int.tryParse(hex, radix: 16) ?? 0xFF4C956C;
    return Color(colorValue);
  }

  Uint8List? _stableTrayIconBytes(String key, Uint8List? next) {
    final cached = _trayIconCache[key];
    if (next == null) return cached;
    if (cached != null && listEquals(cached, next)) return cached;
    _trayIconCache[key] = next;
    return next;
  }
}
