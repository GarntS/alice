import 'package:alicebar/alice_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('showPanel and hidePanel send native method-channel payloads', () async {
    const channel = MethodChannel('alice/test-platform');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final platform = AlicePlatform(methodChannel: channel);
    await platform.showPanel(
      'trayOverflow',
      anchorX: 100.5,
      anchorY: 44,
      alignment: 'right',
      width: 320,
      height: 268,
      includeTrayIconBytes: true,
      panelTopGapPx: 8,
    );
    await platform.hidePanel();

    expect(calls, hasLength(2));
    expect(calls[0].method, 'showPanel');
    expect(calls[0].arguments, <String, Object?>{
      'panelId': 'trayOverflow',
      'anchorX': 100.5,
      'anchorY': 44.0,
      'alignment': 'right',
      'width': 320.0,
      'height': 268.0,
      'includeTrayIconBytes': true,
      'panelTopGapPx': 8,
    });
    expect(calls[1].method, 'hidePanel');
  });
}
