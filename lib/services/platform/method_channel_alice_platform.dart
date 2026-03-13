import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter/services.dart';

import '../../data/alice_config.dart';
import '../../data/bar_snapshot.dart';
const _methodChannelName = 'alice/platform';
const _eventChannelName = 'alice/platform/events';

class MethodChannelAlicePlatform {
  MethodChannelAlicePlatform({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _eventChannel =
           eventChannel ?? const EventChannel(_eventChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Map<String, Uint8List> _trayIconCache = <String, Uint8List>{};

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

  Future<void> sendTrayAction(
    TrayItemSnapshot item, {
    required String action,
    int x = 0,
    int y = 0,
  }) {
    return _methodChannel
        .invokeMethod<void>('sendTrayAction', <String, Object?>{
          'serviceName': item.serviceName,
          'objectPath': item.objectPath,
          'action': action,
          'x': x,
          'y': y,
        });
  }

  Future<void> focusWorkspace(String label) {
    return _methodChannel.invokeMethod<void>(
      'focusWorkspace',
      <String, Object?>{'label': label},
    );
  }

  AliceConfig _configFromMap(Map<Object?, Object?> map) {
    final themeMode = switch (map['themeMode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final accentHex = map['accentColor'] as String? ?? '#4C956C';
    final trayItems = (map['maxVisibleTrayItems'] as num?)?.toInt() ?? 5;
    final showNetworkLabel = map['showNetworkLabel'] as bool? ?? true;
    final localTimeZoneLabel = _stringOrNull(map['localTimeZoneLabel']);
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
      localTimeZoneLabel: localTimeZoneLabel,
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
            albumTitle: mediaMap['albumTitle'] as String? ?? '',
            artUrl: mediaMap['artUrl'] as String? ?? '',
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
    final activeTrayKeys = <String>{};
    final trayItems = (map['trayItems'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((item) {
          final serviceName = item['serviceName'] as String? ?? '';
          final objectPath = item['objectPath'] as String? ?? '';
          final iconKey = '$serviceName|$objectPath';
          activeTrayKeys.add(iconKey);
          return TrayItemSnapshot(
            id: item['id'] as String? ?? '',
            label: item['label'] as String? ?? '',
            serviceName: serviceName,
            objectPath: objectPath,
            iconPngBytes: _stableTrayIconBytes(
              iconKey,
              _uint8ListOrNull(item['iconPngBytes']),
            ),
          );
        })
        .toList();
    _trayIconCache.removeWhere((key, _) => !activeTrayKeys.contains(key));

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

  String? _stringOrNull(Object? value) {
    final text = value as String?;
    if (text == null) {
      return null;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Uint8List? _uint8ListOrNull(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    return null;
  }

  Uint8List? _stableTrayIconBytes(String key, Uint8List? next) {
    final cached = _trayIconCache[key];
    if (next == null) {
      return cached;
    }

    if (cached != null && listEquals(cached, next)) {
      return cached;
    }

    _trayIconCache[key] = next;
    return next;
  }
}
