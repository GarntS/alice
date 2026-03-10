import 'dart:async';

import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter/services.dart';

import '../../models/alice_config.dart';
import '../../models/bar_snapshot.dart';
import 'alice_platform.dart';
import 'channel_names.dart';

class MethodChannelAlicePlatform implements AlicePlatform {
  MethodChannelAlicePlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(aliceMethodChannelName),
       _eventChannel =
           eventChannel ?? const EventChannel(aliceEventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<BarSnapshot> watchBarSnapshots() {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      final map = Map<Object?, Object?>.from(event as Map<Object?, Object?>);
      return _snapshotFromMap(map);
    });
  }

  Future<AliceConfig> loadConfig() async {
    final result = await _methodChannel.invokeMethod<Object?>('loadConfig');
    if (result is! Map<Object?, Object?>) {
      throw StateError('loadConfig returned an unexpected payload');
    }

    return _configFromMap(Map<Object?, Object?>.from(result));
  }

  Future<void> showPanel(
    String panelId, {
    required double anchorX,
    required double anchorY,
    required String alignment,
    required double width,
    required double height,
  }) {
    return _methodChannel.invokeMethod<void>('showPanel', <String, Object?>{
      'panelId': panelId,
      'anchorX': anchorX,
      'anchorY': anchorY,
      'alignment': alignment,
      'width': width,
      'height': height,
    });
  }

  Future<void> hidePanel() {
    return _methodChannel.invokeMethod<void>('hidePanel');
  }

  Future<void> sendMediaAction(String action) {
    return _methodChannel.invokeMethod<void>(
      'sendMediaAction',
      <String, Object?>{'action': action},
    );
  }

  Future<void> executePowerAction(String action) {
    return _methodChannel.invokeMethod<void>(
      'executePowerAction',
      <String, Object?>{'action': action},
    );
  }

  @override
  BarSnapshot get snapshot => const BarSnapshot(
    activePanelId: null,
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

  AliceConfig _configFromMap(Map<Object?, Object?> map) {
    final themeMode = switch (map['themeMode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final accentHex = map['accentColor'] as String? ?? '#4C956C';
    final trayItems = (map['maxVisibleTrayItems'] as num?)?.toInt() ?? 5;
    final showNetworkLabel = map['showNetworkLabel'] as bool? ?? true;
    final timeZoneList =
        (map['timeZones'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (entry) => TimeZoneConfig(
                label: entry['label'] as String? ?? 'UTC',
                offsetHours: (entry['offsetHours'] as num?)?.toInt() ?? 0,
              ),
            )
            .toList();
    final power = Map<Object?, Object?>.from(
      map['powerCommands'] as Map<Object?, Object?>? ??
          const <Object?, Object?>{},
    );

    return AliceConfig(
      themeMode: themeMode,
      accentColor: _colorFromHex(accentHex),
      showNetworkLabel: showNetworkLabel,
      maxVisibleTrayItems: trayItems,
      timeZones: timeZoneList,
      powerCommands: PowerCommandConfig(
        lock: power['lock'] as String? ?? 'loginctl lock-session',
        lockAndSuspend:
            power['lockAndSuspend'] as String? ??
            'loginctl lock-session && systemctl suspend',
        restart: power['restart'] as String? ?? 'systemctl reboot',
        poweroff: power['poweroff'] as String? ?? 'systemctl poweroff',
      ),
    );
  }

  BarSnapshot _snapshotFromMap(Map<Object?, Object?> map) {
    final workspaces =
        (map['workspaces'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (workspace) => WorkspaceSnapshot(
                label: workspace['label'] as String? ?? '?',
                isFocused: workspace['isFocused'] as bool? ?? false,
                isVisible: workspace['isVisible'] as bool? ?? false,
              ),
            )
            .toList();

    final mediaMap = map['media'] as Map<Object?, Object?>?;
    final media = mediaMap == null
        ? null
        : MediaSnapshot(
            title: mediaMap['title'] as String? ?? '',
            artist: mediaMap['artist'] as String? ?? '',
            positionLabel: mediaMap['positionLabel'] as String? ?? '0:00',
            lengthLabel: mediaMap['lengthLabel'] as String? ?? '0:00',
            isPlaying: mediaMap['isPlaying'] as bool? ?? false,
          );

    final networkMap = Map<Object?, Object?>.from(
      map['network'] as Map<Object?, Object?>? ?? const <Object?, Object?>{},
    );
    final clockMap = Map<Object?, Object?>.from(
      map['clock'] as Map<Object?, Object?>? ?? const <Object?, Object?>{},
    );
    final trayItems = (map['trayItems'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => TrayItemSnapshot(
            id: item['id'] as String? ?? '',
            label: item['label'] as String? ?? '',
          ),
        )
        .toList();

    return BarSnapshot(
      activePanelId: map['activePanelId'] as String?,
      workspaces: workspaces,
      media: media,
      memoryUsagePercent: (map['memoryUsagePercent'] as num?)?.toDouble() ?? 0,
      cpuUsageCores: (map['cpuUsageCores'] as num?)?.toDouble() ?? 0,
      network: NetworkSnapshot(
        kind: switch (networkMap['kind']) {
          'wifi' => NetworkKind.wifi,
          'wired' => NetworkKind.wired,
          _ => NetworkKind.disconnected,
        },
        label: networkMap['label'] as String? ?? 'Disconnected',
      ),
      clock: ClockSnapshot(
        timeZoneCode: clockMap['timeZoneCode'] as String? ?? 'UTC',
        dateLabel: clockMap['dateLabel'] as String? ?? '-- ---',
        timeLabel: clockMap['timeLabel'] as String? ?? '--:--',
      ),
      trayItems: trayItems,
    );
  }

  Color _colorFromHex(String value) {
    final normalized = value.replaceFirst('#', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final colorValue = int.tryParse(hex, radix: 16) ?? 0xFF4C956C;
    return Color(colorValue);
  }
}
