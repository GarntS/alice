import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/rust_gen/tray.dart';
import 'package:alicebar/tray_input_router.dart';
import 'package:alicebar/alice_platform.dart';
import 'package:alicebar/widgets/bar_widgets/tray_module.dart';
import 'package:alicebar/widgets/panels/tray_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'helpers/alice_test_helpers.dart';

TrayItemSnapshot inputItem({
  bool menuOnly = false,
  String? menu = '/Menu',
  TrayCapability contextMenu = TrayCapability.unsupported,
}) => TrayItemSnapshot(
  id: 'input',
  label: 'Input',
  serviceName: 'org.example.Input',
  objectPath: '/Item',
  iconPngBytes: null,
  status: 'Active',
  itemIsMenu: menuOnly,
  menuPath: menu,
  activate: TrayCapability.unknown,
  secondaryActivate: TrayCapability.unsupported,
  contextMenu: contextMenu,
);
void main() {
  const anchor = PanelAnchor(
    sourceViewId: 7,
    globalPosition: Offset(100, 44),
    alignment: PanelAlignment.right,
  );
  const screen = Offset(2020, 44);
  test(
    'primary activation only falls back on explicit unsupported outcomes',
    () async {
      for (final outcome in [
        const TrayActionOutcome.executed(),
        const TrayActionOutcome.unsupported(),
        const TrayActionOutcome.failed(reason: 'remote error'),
      ]) {
        final calls = <String>[];
        final diagnostics = <String>[];
        final router = TrayInputRouter(
          sendAction: (_, method, point) async {
            expect(point, screen);
            calls.add(method);
            return outcome;
          },
          openMenu: (_, source, point) async {
            expect(source, same(anchor));
            expect(point, screen);
            calls.add('menu');
            return true;
          },
          diagnostic: diagnostics.add,
        );
        await router.route(inputItem(), anchor, screen, secondary: false);
        expect(
          calls,
          outcome is TrayActionOutcome_Unsupported
              ? ['activate', 'menu']
              : ['activate'],
        );
        if (outcome is TrayActionOutcome_Failed)
          expect(diagnostics, ['remote error']);
      }
    },
  );
  test(
    'menu-only items bypass activation and right-click prefers menus',
    () async {
      final calls = <String>[];
      final router = TrayInputRouter(
        sendAction: (_, method, _) async {
          calls.add(method);
          return const TrayActionOutcome.executed();
        },
        openMenu: (_, _, _) async {
          calls.add('menu');
          return true;
        },
        diagnostic: (_) {},
      );
      await router.route(
        inputItem(menuOnly: true),
        anchor,
        screen,
        secondary: false,
      );
      await router.route(
        inputItem(contextMenu: TrayCapability.supported),
        anchor,
        screen,
        secondary: true,
      );
      expect(calls, ['menu', 'menu']);
    },
  );
  test(
    'right-click fallback only dispatches confirmed ContextMenu support',
    () async {
      for (final capability in TrayCapability.values) {
        final calls = <String>[];
        final router = TrayInputRouter(
          sendAction: (_, method, _) async {
            calls.add(method);
            return const TrayActionOutcome.executed();
          },
          openMenu: (_, _, _) async => false,
          diagnostic: (_) {},
        );
        await router.route(
          inputItem(menu: null, contextMenu: capability),
          anchor,
          screen,
          secondary: true,
        );
        expect(
          calls,
          capability == TrayCapability.supported ? ['contextMenu'] : isEmpty,
        );
      }
    },
  );
  test('bridge errors are diagnosed without duplicate dispatch', () async {
    final diagnostics = <String>[];
    var menus = 0;
    var actions = 0;
    final router = TrayInputRouter(
      sendAction: (_, _, _) async {
        actions++;
        throw StateError('transport error');
      },
      openMenu: (_, _, _) async {
        menus++;
        return true;
      },
      diagnostic: diagnostics.add,
    );
    await router.route(inputItem(), anchor, screen, secondary: false);
    expect(actions, 1);
    expect(menus, 0);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single, contains('transport error'));
  });
  test('superseded input never opens a fallback menu', () async {
    var current = true;
    var opened = false;
    final router = TrayInputRouter(
      isCurrent: () => current,
      sendAction: (_, _, _) async {
        current = false;
        return const TrayActionOutcome.unsupported();
      },
      openMenu: (_, _, _) async {
        opened = true;
        return true;
      },
    );
    await router.route(inputItem(), anchor, screen, secondary: false);
    expect(opened, isFalse);
  });
  for (final overflow in [false, true]) {
    testWidgets(
      '${overflow ? "overflow" : "bar"} routes both buttons and ignores middle-click',
      (tester) async {
        final clicks = <bool>[];
        final anchors = <PanelAnchor>[];
        final item = inputItem();
        void input(TrayItemSnapshot _, PanelAnchor anchor, bool secondary) {
          clicks.add(secondary);
          anchors.add(anchor);
        }

        final child = overflow
            ? TrayPanel(
                trayItems: [item],
                maxVisibleTrayItems: 1,
                onTrayAction: (_) async {},
                onTrayInput: input,
              )
            : TopBarTrayGroupModule(
                items: [item],
                onItemTap: (_) {},
                onInput: input,
              );
        await pumpAliceWidget(tester, child);
        final target = overflow
            ? find.text('Input')
            : find.byType(Semantics).last;
        await tester.tap(target);
        await tester.tap(target, buttons: kSecondaryMouseButton);
        await tester.tap(target, buttons: kMiddleMouseButton);
        expect(clicks, [false, true]);
        expect(
          anchors.every((anchor) => anchor.sourceViewId == tester.view.viewId),
          isTrue,
        );
        expect(
          anchors.every((anchor) => anchor.globalPosition != Offset.zero),
          isTrue,
        );
      },
    );
  }
  test(
    'native anchor captures monitor coordinates before any surface closes',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('alice/platform');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'resolveTrayAnchor');
            expect(call.arguments, {'viewId': 7, 'x': 100.0, 'y': 44.0});
            return {
              'sourceViewId': 7,
              'x': 600.0,
              'y': 100.0,
              'screenX': 2520.0,
              'screenY': 100.0,
              'width': 1920.0,
              'height': 1036.0,
              'barHeight': 44.0,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final resolved = await AlicePlatform().resolveTrayAnchor(anchor);
      expect(resolved.anchor.sourceViewId, 7);
      expect(resolved.screenPosition, const Offset(2520, 100));
      expect(resolved.popupPosition, const Offset(600, 56));
      expect(resolved.usableSize, const Size(1920, 1036));
    },
  );
}
