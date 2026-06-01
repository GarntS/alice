import 'package:alicebar/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known panel ids and ignores unknown ids', () {
    expect(alicePanelFromId('media'), AlicePanel.media);
    expect(alicePanelFromId('clock'), AlicePanel.clock);
    expect(alicePanelFromId('weather'), AlicePanel.weather);
    expect(alicePanelFromId('trayOverflow'), AlicePanel.trayOverflow);
    expect(alicePanelFromId('power'), AlicePanel.power);
    expect(alicePanelFromId('notifications'), AlicePanel.notifications);
    expect(alicePanelFromId('missing'), isNull);
    expect(alicePanelFromId(null), isNull);
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

    controller.dispose();
  });
}
