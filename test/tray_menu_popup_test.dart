import 'dart:async';
import 'package:alicebar/alice_platform.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/rust_gen/tray.dart';
import 'package:alicebar/rust_gen/tray_menu.dart';
import 'package:alicebar/rust_gen/tray_menu_service.dart';
import 'package:alicebar/tray_anchor.dart';
import 'package:alicebar/tray_menu_controller.dart';
import 'package:alicebar/widgets/tray_menu_popup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';
import 'helpers/alice_test_helpers.dart';

TrayMenuNode node(
  int id,
  String label, {
  bool enabled = true,
  bool visible = true,
  bool separator = false,
  TrayMenuToggle toggle = TrayMenuToggle.none,
  List<TrayMenuNode> children = const [],
}) => TrayMenuNode(
  id: id,
  label: label,
  visible: visible,
  enabled: enabled,
  separator: separator,
  submenu: children.isNotEmpty,
  toggle: toggle,
  toggleState: toggle == TrayMenuToggle.none ? -1 : 1,
  children: children,
);
TrayItemSnapshot menuItem() => TrayItemSnapshot(
  id: 'menu',
  label: 'Menu',
  serviceName: 'org.example.Menu',
  objectPath: '/Item',
  iconPngBytes: null,
  status: 'Active',
  itemIsMenu: true,
  menuPath: '/Menu',
  activate: TrayCapability.unsupported,
  secondaryActivate: TrayCapability.supported,
  contextMenu: TrayCapability.unsupported,
);

class MenuPlatform extends AlicePlatform {
  MenuPlatform({this.secondary = true});
  final bool secondary;
  final List<BigInt> cancelled = [];
  final List<TrayMenuSelection> selected = [];
  final List<int> prepared = [];
  final List<int> sources = [];
  PanelController? panels;
  bool? overflowPresentDuringCapture;
  Completer<TrayMenuSnapshot>? pending;
  TrayMenuUpdate update = const TrayMenuUpdate.unchanged();
  int next = 0;
  TrayMenuSnapshot snapshot(BigInt id) => TrayMenuSnapshot(
    requestId: id,
    revision: 1,
    secondarySupported: secondary,
    root: node(
      0,
      '',
      children: [
        node(1, 'Disabled', enabled: false),
        node(2, 'Hidden', visible: false),
        node(3, '', separator: true),
        node(4, '_Check', toggle: TrayMenuToggle.check),
        node(5, '_Radio', toggle: TrayMenuToggle.radio),
        node(6, 'Models', children: [node(7, 'Choice')]),
      ],
    ),
  );
  @override
  Future<TrayResolvedAnchor> resolveTrayAnchor(PanelAnchor anchor) async {
    sources.add(anchor.sourceViewId);
    overflowPresentDuringCapture = panels?.openPanel == AlicePanel.trayOverflow;
    return TrayResolvedAnchor(
      anchor: const PanelAnchor(
        sourceViewId: 7,
        globalPosition: Offset(390, 290),
        alignment: PanelAlignment.right,
      ),
      screenPosition: const Offset(2310, 290),
      usableSize: const Size(400, 300),
      popupPosition: const Offset(390, 246),
    );
  }

  @override
  Future<BigInt> beginTrayMenuRequest() async => BigInt.from(++next);
  @override
  Future<TrayMenuSnapshot> loadTrayMenu(
    BigInt requestId,
    TrayItemSnapshot item,
  ) => pending?.future ?? Future.value(snapshot(requestId));
  @override
  Future<TrayMenuUpdate> refreshTrayMenu(
    BigInt requestId, {
    int? submenuId,
  }) async {
    if (submenuId != null) prepared.add(submenuId);
    return update;
  }

  @override
  Future<void> cancelTrayMenu(BigInt requestId) async {
    cancelled.add(requestId);
  }

  @override
  Future<TrayActionOutcome> selectTrayMenu(
    BigInt requestId,
    TrayMenuSelection selection, {
    required int x,
    required int y,
    required int timestamp,
  }) async {
    expect((x, y), (2310, 290));
    selected.add(selection);
    return const TrayActionOutcome.executed();
  }
}

class LongMenuPlatform extends MenuPlatform {
  LongMenuPlatform() : super(secondary: false);
  @override
  TrayMenuSnapshot snapshot(BigInt id) => TrayMenuSnapshot(
    requestId: id,
    revision: 1,
    secondarySupported: false,
    root: node(
      0,
      '',
      children: List.generate(
        100,
        (index) => node(index + 1, 'Long ${index + 1}'),
      ),
    ),
  );
}

Future<TrayMenuController> open(
  MenuPlatform platform,
  PanelController panels,
) async {
  platform.panels = panels;
  final controller = TrayMenuController(platform, panels);
  await controller.handle(
    menuItem(),
    const PanelAnchor(
      sourceViewId: 12,
      globalPosition: Offset(100, 100),
      alignment: PanelAlignment.right,
    ),
    false,
  );
  return controller;
}

void main() {
  for (final overflow in [false, true]) {
    test(
      '${overflow ? "overflow" : "bar"} captures its origin before popup replacement',
      () async {
        final platform = MenuPlatform();
        final panels = PanelController();
        platform.panels = panels;
        const anchor = PanelAnchor(
          sourceViewId: 7,
          globalPosition: Offset(300, 44),
          alignment: PanelAlignment.right,
        );
        if (overflow) panels.toggle(AlicePanel.trayOverflow, anchor);
        final controller = TrayMenuController(platform, panels);
        await controller.handle(
          menuItem(),
          PanelAnchor(
            sourceViewId: overflow ? 12 : 7,
            globalPosition: const Offset(100, 100),
            alignment: PanelAlignment.right,
          ),
          false,
        );
        expect(platform.overflowPresentDuringCapture, overflow);
        expect(platform.sources, [overflow ? 12 : 7]);
        expect(panels.openPanel, AlicePanel.trayMenu);
        expect(panels.sourceViewId, 7);
        panels.toggle(AlicePanel.media, anchor);
        expect(controller.snapshot, isNull);
        expect(platform.cancelled, contains(BigInt.one));
        controller.dispose();
        panels.dispose();
      },
    );
  }
  test(
    'a superseded pending load cannot reopen or close the new popup',
    () async {
      final platform = MenuPlatform();
      final panels = PanelController();
      final controller = TrayMenuController(platform, panels);
      final pending = Completer<TrayMenuSnapshot>();
      platform.pending = pending;
      const anchor = PanelAnchor(
        sourceViewId: 7,
        globalPosition: Offset.zero,
        alignment: PanelAlignment.right,
      );
      final first = controller.handle(menuItem(), anchor, false);
      await Future<void>.delayed(Duration.zero);
      platform.pending = null;
      await controller.handle(menuItem(), anchor, false);
      expect(controller.snapshot?.requestId, BigInt.two);
      pending.complete(platform.snapshot(BigInt.one));
      await first;
      expect(controller.snapshot?.requestId, BigInt.two);
      expect(panels.openPanel, AlicePanel.trayMenu);
      expect(platform.cancelled, contains(BigInt.one));
      controller.dispose();
      panels.dispose();
    },
  );
  testWidgets(
    'live updates replace stale rows and owner loss closes the popup',
    (tester) async {
      final platform = MenuPlatform();
      final panels = PanelController();
      final controller = await open(platform, panels);
      addTearDown(() {
        controller.dispose();
        panels.dispose();
      });
      await pumpAliceWidget(
        tester,
        TrayMenuPopup(controller: controller),
        size: const Size(400, 300),
      );
      await tester.pump();
      platform.update = TrayMenuUpdate.updated(
        snapshot: TrayMenuSnapshot(
          requestId: BigInt.one,
          revision: 2,
          secondarySupported: false,
          root: node(0, '', children: [node(101, 'Replacement')]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Check'), findsNothing);
      expect(find.text('Replacement'), findsOneWidget);
      platform.update = const TrayMenuUpdate.closed();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(panels.openPanel, isNull);
      expect(controller.snapshot, isNull);
      expect(find.text('Replacement'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('context-menu positions clamp to usable output bounds', () {
    expect(
      clampTrayMenuPosition(
        const Offset(-30, 1000),
        const Size(240, 300),
        const Size(400, 300),
      ),
      Offset.zero,
    );
    expect(
      clampTrayMenuPosition(
        const Offset(1000, -20),
        const Size(240, 100),
        const Size(400, 300),
      ),
      const Offset(160, 0),
    );
  });
  testWidgets(
    'keyboard opens and closes bounded submenus and activates remote entries',
    (tester) async {
      final platform = MenuPlatform();
      final panels = PanelController();
      final controller = await open(platform, panels);
      addTearDown(() {
        controller.dispose();
        panels.dispose();
      });
      await pumpAliceWidget(
        tester,
        TrayMenuPopup(controller: controller),
        size: const Size(400, 300),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(platform.prepared, [6]);
      expect(find.text('Choice'), findsOneWidget);
      final rect = tester.getRect(find.text('Choice'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(400));
      expect(rect.bottom, lessThanOrEqualTo(300));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('Choice'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(platform.selected.single, const TrayMenuSelection.remote(id: 7));
      expect(panels.openPanel, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('long menus scroll within bounds and Escape releases the popup', (
    tester,
  ) async {
    final platform = LongMenuPlatform();
    final panels = PanelController();
    final controller = await open(platform, panels);
    addTearDown(() {
      controller.dispose();
      panels.dispose();
    });
    await pumpAliceWidget(
      tester,
      TrayMenuPopup(controller: controller),
      size: const Size(400, 300),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(
      tester.getRect(find.text('Long 100')).bottom,
      lessThanOrEqualTo(300),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panels.openPanel, isNull);
    expect(platform.cancelled, contains(BigInt.one));
    expect(find.text('Long 100'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('clicking transparent space completely dismisses the menu', (
    tester,
  ) async {
    final platform = MenuPlatform();
    final panels = PanelController();
    final controller = await open(platform, panels);
    addTearDown(() {
      controller.dispose();
      panels.dispose();
    });
    await pumpAliceWidget(
      tester,
      TrayMenuPopup(controller: controller),
      size: const Size(400, 300),
    );
    await tester.pump();
    await tester.tapAt(const Offset(399, 1));
    await tester.pump();
    expect(panels.openPanel, isNull);
    expect(controller.snapshot, isNull);
    expect(find.text('Secondary action'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'conventional rows include conditional secondary, separators and toggles',
    (tester) async {
      final platform = MenuPlatform();
      final panels = PanelController();
      final controller = await open(platform, panels);
      addTearDown(() {
        controller.dispose();
        panels.dispose();
      });
      await pumpAliceWidget(
        tester,
        TrayMenuPopup(controller: controller),
        size: const Size(400, 300),
      );
      await tester.pump();
      expect(find.text('Secondary action'), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Check'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('●'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Secondary action')).dy,
        lessThan(tester.getTopLeft(find.text('Check')).dy),
      );
      await tester.tap(find.text('Disabled'));
      expect(platform.selected, isEmpty);
      expect(panels.openPanel, AlicePanel.trayMenu);
      await tester.tap(find.text('Secondary action'));
      await tester.pump();
      expect(platform.selected.single, const TrayMenuSelection.secondary());
      expect(panels.openPanel, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('unsupported SecondaryActivate omits the synthetic row', (
    tester,
  ) async {
    final platform = MenuPlatform(secondary: false);
    final panels = PanelController();
    final controller = await open(platform, panels);
    addTearDown(() {
      controller.dispose();
      panels.dispose();
    });
    await pumpAliceWidget(
      tester,
      TrayMenuPopup(controller: controller),
      size: const Size(400, 300),
    );
    await tester.pump();
    expect(find.text('Secondary action'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    controller.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
