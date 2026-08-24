import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/notification_popups.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  Widget host({
    required List<NotificationSnapshot> notifications,
    void Function(int id)? onDismissPopupRead,
    void Function(int id)? onDismissNotification,
    void Function(int id)? onMarkRead,
    void Function(int id, String key)? onInvokeAction,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: NotificationPopupStack(
          notifications: notifications,
          onDismissPopupRead: onDismissPopupRead ?? (_) {},
          onDismissNotification: onDismissNotification ?? (_) {},
          onMarkRead: onMarkRead ?? (_) {},
          onInvokeAction: onInvokeAction ?? (_, __) {},
        ),
      ),
    );
  }

  testWidgets('renders popups in supplied oldest-to-newest order', (
    tester,
  ) async {
    final notifications = testNotifications(3);

    await tester.pumpWidget(host(notifications: notifications));

    final first = tester.getTopLeft(find.text('Summary 0'));
    final last = tester.getTopLeft(find.text('Summary 2'));
    expect(first.dy, lessThan(last.dy));
  });

  testWidgets('body tap marks read without removing popup', (tester) async {
    final marked = <int>[];
    final notifications = testNotifications(1);

    await tester.pumpWidget(
      host(notifications: notifications, onMarkRead: marked.add),
    );
    await tester.tap(find.text('Summary 0'));

    expect(marked, [notifications.first.id]);
    expect(find.text('Summary 0'), findsOneWidget);
  });

  testWidgets('action tap invokes action callback', (tester) async {
    final actions = <String>[];
    final notifications = testNotifications(1);

    await tester.pumpWidget(
      host(
        notifications: notifications,
        onInvokeAction: (id, key) => actions.add('$id:$key'),
      ),
    );
    await tester.tap(find.text('Open'));

    expect(actions, ['${notifications.first.id}:default']);
  });

  testWidgets('rightward dismissal marks popup read', (tester) async {
    final dismissed = <int>[];
    final notifications = testNotifications(1);

    await tester.pumpWidget(
      host(notifications: notifications, onDismissPopupRead: dismissed.add),
    );
    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(dismissed, [notifications.first.id]);
  });
}
