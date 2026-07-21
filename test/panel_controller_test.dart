import 'package:alicebar/panel_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('panel ids are canonical and round-trip', () {
    const expectedIds = <AlicePanel, String>{
      AlicePanel.media: 'media',
      AlicePanel.clock: 'clock',
      AlicePanel.tasks: 'tasks',
      AlicePanel.weather: 'weather',
      AlicePanel.trayOverflow: 'trayOverflow',
      AlicePanel.power: 'power',
      AlicePanel.notifications: 'notifications',
    };

    expect(AlicePanel.values, orderedEquals(expectedIds.keys));
    for (final panel in AlicePanel.values) {
      expect(panel.id, expectedIds[panel]);
      expect(alicePanelFromId(panel.id), panel);
    }
    expect(alicePanelFromId('missing'), isNull);
    expect(alicePanelFromId(null), isNull);
  });

  test('every panel has a stable initially-false listenable', () {
    final controller = PanelController();
    final namedListenables = <AlicePanel, ValueListenable<bool>>{
      AlicePanel.media: controller.mediaOpen,
      AlicePanel.clock: controller.clockOpen,
      AlicePanel.tasks: controller.tasksOpen,
      AlicePanel.weather: controller.weatherOpen,
      AlicePanel.trayOverflow: controller.trayOverflowOpen,
      AlicePanel.power: controller.powerOpen,
      AlicePanel.notifications: controller.notificationsOpen,
    };

    for (final panel in AlicePanel.values) {
      final listenable = controller.openListenable(panel);
      expect(listenable, same(controller.openListenable(panel)));
      expect(namedListenables[panel], same(listenable));
      expect(listenable.value, isFalse);
    }

    controller.dispose();
  });

  test('disposing the controller disposes every panel listenable', () {
    final controller = PanelController();
    final listenables = AlicePanel.values
        .map(controller.openListenable)
        .toList();

    controller.dispose();

    for (final listenable in listenables) {
      expect(() => listenable.addListener(() {}), throwsFlutterError);
    }
  });

  test('toggle tracks a single open panel and anchor', () {
    final controller = PanelController();
    final mediaAnchor = PanelAnchor(
      globalPosition: const Offset(10, 20),
      alignment: PanelAlignment.center,
    );
    final powerAnchor = PanelAnchor(
      globalPosition: const Offset(30, 40),
      alignment: PanelAlignment.right,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.toggle(AlicePanel.media, mediaAnchor);
    expect(controller.openPanel, AlicePanel.media);
    expect(controller.anchor, same(mediaAnchor));
    expect(notifications, 1);

    controller.toggle(AlicePanel.power, powerAnchor);
    expect(controller.openPanel, AlicePanel.power);
    expect(controller.anchor, same(powerAnchor));
    expect(notifications, 2);

    controller.toggle(AlicePanel.power, powerAnchor);
    expect(controller.openPanel, isNull);
    expect(controller.anchor, isNull);
    expect(notifications, 3);

    controller.close();
    expect(controller.openPanel, isNull);
    expect(controller.anchor, isNull);
    expect(notifications, 3);

    controller.dispose();
  });

  test('granular open-state listeners notify only changed panels', () {
    final controller = PanelController();
    final mediaAnchor = PanelAnchor(
      globalPosition: const Offset(10, 20),
      alignment: PanelAlignment.center,
    );
    final clockAnchor = PanelAnchor(
      globalPosition: const Offset(30, 40),
      alignment: PanelAlignment.right,
    );
    final weatherAnchor = PanelAnchor(
      globalPosition: const Offset(50, 60),
      alignment: PanelAlignment.right,
    );
    final counts = <AlicePanel, int>{};
    for (final panel in AlicePanel.values) {
      controller.openListenable(panel).addListener(() {
        counts[panel] = (counts[panel] ?? 0) + 1;
      });
    }

    controller.toggle(AlicePanel.media, mediaAnchor);
    expect(counts, {AlicePanel.media: 1});
    expect(controller.mediaOpen.value, isTrue);
    expect(controller.clockOpen.value, isFalse);
    expect(controller.weatherOpen.value, isFalse);

    controller.toggle(AlicePanel.clock, clockAnchor);
    expect(counts[AlicePanel.media], 2);
    expect(counts[AlicePanel.clock], 1);
    expect(counts.length, 2);
    expect(controller.mediaOpen.value, isFalse);
    expect(controller.clockOpen.value, isTrue);
    expect(controller.weatherOpen.value, isFalse);

    controller.toggle(AlicePanel.weather, weatherAnchor);
    expect(counts[AlicePanel.clock], 2);
    expect(counts[AlicePanel.weather], 1);
    expect(controller.clockOpen.value, isFalse);
    expect(controller.weatherOpen.value, isTrue);

    controller.toggle(AlicePanel.weather, weatherAnchor);
    expect(counts[AlicePanel.weather], 2);
    expect(counts.length, 3);
    expect(controller.weatherOpen.value, isFalse);

    controller.close();
    expect(counts[AlicePanel.weather], 2);
    expect(counts.length, 3);

    controller.dispose();
  });
}
