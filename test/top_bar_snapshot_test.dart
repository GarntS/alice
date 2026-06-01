import 'package:alicebar/alice_config.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets('top bar renders a mixed snapshot without throwing', (
    tester,
  ) async {
    final controller = PanelController();
    final tappedWorkspaces = <String>[];
    final tappedTrayItems = <TrayItemSnapshot>[];

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1600,
        height: 80,
        child: TopBar(
          config: testConfig(
            maxVisibleTrayItems: 3,
            weather: const WeatherConfig(
              enable: false,
              pirateWeatherKey: null,
              forecastLat: null,
              forecastLong: null,
              forecastLanguage: 'en',
              forecastUnits: 'us',
              refreshInterval: 3600,
              locationLabel: null,
            ),
          ),
          snapshotState: testSnapshotState(snapshot: testSnapshot()),
          panelController: controller,
          onWorkspaceTap: tappedWorkspaces.add,
          onTrayItemTap: tappedTrayItems.add,
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1700, 120),
    );

    expectNoFlutterErrors();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final workspaceDecoration = _workspaceGroupDecoration(tester);
    expect(workspaceDecoration.color, isNotNull);
    expect(workspaceDecoration.borderRadius, BorderRadius.circular(14));
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

  testWidgets('top bar shell decoration follows transparency config', (
    tester,
  ) async {
    final controller = PanelController();

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1000,
        height: 80,
        child: TopBar(
          config: testConfig(),
          snapshotState: testSnapshotState(snapshot: testSnapshot()),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1100, 120),
    );

    var decoration = _topBarShellDecoration(tester);
    expect(decoration.color, isNotNull);
    expect(decoration.border, isNotNull);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1000,
        height: 80,
        child: TopBar(
          config: testConfig(transparentTopBar: true),
          snapshotState: testSnapshotState(snapshot: testSnapshot()),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1100, 120),
    );

    decoration = _topBarShellDecoration(tester);
    expect(decoration.color, isNull);
    expect(decoration.border, isNull);

    controller.dispose();
  });

  testWidgets('top bar renders weather data and no-data placeholder', (
    tester,
  ) async {
    final controller = PanelController();
    addTearDown(controller.dispose);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1300,
        height: 80,
        child: TopBar(
          config: testConfig(),
          snapshotState: testSnapshotState(
            snapshot: testSnapshot(weather: testWeather()),
          ),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1500, 140),
    );
    expectNoFlutterErrors();
    expect(find.text('50°F'), findsOneWidget);

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1300,
        height: 80,
        child: TopBar(
          config: testConfig(),
          snapshotState: testSnapshotState(snapshot: testSnapshot()),
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1500, 140),
    );
    expectNoFlutterErrors();
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('top bar tolerates hidden network label and no media', (
    tester,
  ) async {
    final controller = PanelController();

    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1000,
        height: 80,
        child: TopBar(
          config: testConfig(showNetworkLabel: false),
          snapshotState: testSnapshotState(
            snapshot: testSnapshot(
              media: null,
              network: const NetworkSnapshot(
                kind: NetworkKind.disconnected,
                label: 'Disconnected',
              ),
              trayItems: const [],
              notifications: const [],
            ),
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

BoxDecoration _topBarShellDecoration(WidgetTester tester) {
  final container = tester
      .widgetList<Container>(find.byType(Container))
      .singleWhere(
        (container) =>
            container.padding ==
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      );
  return container.decoration! as BoxDecoration;
}

BoxDecoration _workspaceGroupDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('top-bar-workspace-group-background')),
  );
  return container.decoration! as BoxDecoration;
}
