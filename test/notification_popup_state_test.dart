import 'package:alicebar/alice_config.dart';
import 'package:alicebar/notification_popup_state.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

NotificationConfig popupConfig({
  bool show = true,
  int displayMs = 5000,
  bool expireCritical = false,
}) {
  return NotificationConfig(
    defaultTimeoutMs: 5000,
    showNotificationPopup: show,
    notificationDisplayTimeMs: displayMs,
    expireCriticalNotifications: expireCritical,
  );
}

void main() {
  testWidgets('orders popups oldest-to-newest and enforces max-four FIFO', (
    tester,
  ) async {
    final state = NotificationPopupState(
      config: testConfig(notifications: popupConfig(displayMs: 0)),
    );

    state.processSnapshot(testNotifications(5));

    expect(state.visibleIds, [2, 3, 4, 5]);
    state.dispose();
  });

  testWidgets('suppresses popup creation when disabled', (tester) async {
    final state = NotificationPopupState(
      config: testConfig(notifications: popupConfig(show: false)),
    );

    state.processSnapshot(testNotifications(2));

    expect(state.visibleIds, isEmpty);
    state.dispose();
  });

  testWidgets('hideAll clears visible popups for panel-open behavior', (
    tester,
  ) async {
    final state = NotificationPopupState(
      config: testConfig(notifications: popupConfig(displayMs: 0)),
    );
    state.processSnapshot(testNotifications(2));

    expect(state.hideAll(), isTrue);

    expect(state.visibleIds, isEmpty);
    state.dispose();
  });

  testWidgets('replacement notification resets popup timer', (tester) async {
    var changes = 0;
    final state = NotificationPopupState(
      config: testConfig(notifications: popupConfig(displayMs: 100)),
      onChanged: () => changes++,
    );
    final first = testNotifications(1).first;
    state.processSnapshot([first]);
    await tester.pump(const Duration(milliseconds: 60));
    final replacement = NotificationSnapshot(
      id: first.id,
      appName: first.appName,
      appIcon: first.appIcon,
      summary: '${first.summary} updated',
      body: first.body,
      urgency: first.urgency,
      actions: first.actions,
      category: first.category,
      isRead: first.isRead,
      receivedAtUnixSecs: first.receivedAtUnixSecs + BigInt.one,
      imageData: first.imageData,
      imagePath: first.imagePath,
    );

    state.processSnapshot([replacement]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(state.visibleIds, [first.id]);
    await tester.pump(const Duration(milliseconds: 50));

    expect(state.visibleIds, isEmpty);
    expect(changes, 1);
    state.dispose();
  });

  testWidgets('timeout removes popup without marking read callback', (
    tester,
  ) async {
    var changes = 0;
    final state = NotificationPopupState(
      config: testConfig(notifications: popupConfig(displayMs: 50)),
      onChanged: () => changes++,
    );

    state.processSnapshot([testNotifications(1).first]);
    await tester.pump(const Duration(milliseconds: 60));

    expect(state.visibleIds, isEmpty);
    expect(changes, 1);
    state.dispose();
  });

  testWidgets('critical expiration obeys expireCriticalNotifications', (
    tester,
  ) async {
    final critical = testNotifications(2)[1];
    expect(critical.urgency, NotificationUrgency.critical);
    final persistent = NotificationPopupState(
      config: testConfig(notifications: popupConfig(displayMs: 50)),
    );
    persistent.processSnapshot([critical]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(persistent.visibleIds, [critical.id]);
    persistent.dispose();

    final expiring = NotificationPopupState(
      config: testConfig(
        notifications: popupConfig(displayMs: 50, expireCritical: true),
      ),
    );
    expiring.processSnapshot([critical]);
    await tester.pump(const Duration(milliseconds: 60));
    expect(expiring.visibleIds, isEmpty);
    expiring.dispose();
  });
}
