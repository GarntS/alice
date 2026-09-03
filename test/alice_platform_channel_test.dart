import 'package:alicebar/alice_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('showPanel and hidePanel send native method-channel payloads', () async {
    const channel = MethodChannel('alice/test-platform');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'showNotificationPopups') return 42;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final platform = AlicePlatform(methodChannel: channel);
    await platform.showPanel(
      'trayOverflow',
      sourceViewId: 42,
      anchorX: 100.5,
      anchorY: 44,
      alignment: 'right',
      width: 320,
      height: 268,
      includeTrayIconBytes: true,
      panelTopGapPx: 8,
    );
    final popupViewIdFuture = platform.showNotificationPopups(panelTopGapPx: 8);
    await platform.hideNotificationPopups();
    await platform.hidePanel();
    final popupViewId = await popupViewIdFuture;

    expect(calls, hasLength(4));
    expect(calls[0].method, 'showPanel');
    expect(calls[0].arguments, <String, Object?>{
      'panelId': 'trayOverflow',
      'sourceViewId': 42,
      'anchorX': 100.5,
      'anchorY': 44.0,
      'alignment': 'right',
      'width': 320.0,
      'height': 268.0,
      'includeTrayIconBytes': true,
      'panelTopGapPx': 8,
    });
    expect(calls[1].method, 'showNotificationPopups');
    expect(calls[1].arguments, <String, Object?>{'panelTopGapPx': 8});
    expect(popupViewId, 42);
    expect(calls[2].method, 'hideNotificationPopups');
    expect(calls[3].method, 'hidePanel');
  });
}
