import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets('top bar renders a mixed snapshot without throwing', (tester) async {
    final controller = PanelController();
    final tappedWorkspaces = <String>[];
    final tappedTrayItems = <TrayItemSnapshot>[];

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1200,
        height: 80,
        child: TopBar(
          config: testConfig(maxVisibleTrayItems: 3),
          snapshot: testSnapshot(),
          panelController: controller,
          onWorkspaceTap: tappedWorkspaces.add,
          onTrayItemTap: tappedTrayItems.add,
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1300, 120),
    );

    expectNoFlutterErrors();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('A Very Testable Song'), findsOneWidget);
    expect(find.text('alice-net'), findsOneWidget);
    expect(find.textContaining('09 Mar'), findsOneWidget);
    expect(find.textContaining('13:37'), findsOneWidget);
    expect(find.text('3 more'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(tappedWorkspaces, contains('1'));

    await tester.tap(find.bySemanticsLabel('Tray Item 0'));
    await tester.pump();
    expect(tappedTrayItems.single.id, 'tray-0');

    controller.dispose();
  });

  testWidgets('top bar tolerates hidden network label and no media', (tester) async {
    final controller = PanelController();

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1000,
        height: 80,
        child: TopBar(
          config: testConfig(showNetworkLabel: false),
          snapshot: testSnapshot(
            media: null,
            network: const NetworkSnapshot(kind: NetworkKind.disconnected, label: 'Disconnected'),
            trayItems: const [],
            notifications: const [],
          ),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1100, 120),
    );

    expectNoFlutterErrors();
    expect(find.textContaining('A Very Testable Song'), findsNothing);
    expect(find.text('Disconnected'), findsNothing);

    controller.dispose();
  });
}
