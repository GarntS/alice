import 'package:alicebar/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known panel ids and ignores unknown ids', () {
    expect(alicePanelFromId('media'), AlicePanel.media);
    expect(alicePanelFromId('clock'), AlicePanel.clock);
    expect(alicePanelFromId('trayOverflow'), AlicePanel.trayOverflow);
    expect(alicePanelFromId('power'), AlicePanel.power);
    expect(alicePanelFromId('notifications'), AlicePanel.notifications);
    expect(alicePanelFromId('missing'), isNull);
    expect(alicePanelFromId(null), isNull);
  });

  test('toggle tracks a single open panel and anchor', () {
    final controller = PanelController();
    final mediaAnchor = PanelAnchor(globalPosition: const Offset(10, 20), alignment: PanelAlignment.center);
    final powerAnchor = PanelAnchor(globalPosition: const Offset(30, 40), alignment: PanelAlignment.right);
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
}
