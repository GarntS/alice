import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/caldav/models.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:alicebar/widgets/bar_widgets/task_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets(
    'task module renders counts, zero, error, semantics, and toggle',
    (tester) async {
      PanelAnchor? anchor;
      Future<void> pump({
        int today = 0,
        int overdue = 0,
        CalDavFreshness freshness = CalDavFreshness.current,
        bool highlighted = false,
      }) => pumpAliceWidget(
        tester,
        TopBarTaskModule(
          dueTodayCount: today,
          overdueCount: overdue,
          syncState: CalDavSyncState(freshness: freshness, hasCachedData: true),
          highlighted: highlighted,
          onToggle: (value) => anchor = value,
        ),
      );

      await pump(today: 2, overdue: 3);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-module-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('task-module-overdue')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Tasks, 2 due today, 3 overdue'),
        findsOneWidget,
      );
      await tester.tap(find.byType(TopBarTaskModule));
      expect(anchor?.alignment, PanelAlignment.right);

      await pump();
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AliceIcon && widget.icon == AliceIcons.listChecks,
        ),
        findsOneWidget,
      );

      await pump(freshness: CalDavFreshness.error, highlighted: true);
      expect(find.byKey(const ValueKey('task-module-error')), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(
        find.bySemanticsLabel('Tasks, synchronization error'),
        findsOneWidget,
      );
    },
  );
}
