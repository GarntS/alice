import 'package:alicebar/alice_theme.dart';
import 'package:alicebar/widgets/bar_widgets/workspace_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  const accent = Color(0xFF4C956C);

  test('builds explicit, brightness-specific Alice color tokens', () {
    final light = buildAliceColorTokens(testConfig(), Brightness.light);
    final dark = buildAliceColorTokens(testConfig(), Brightness.dark);

    expect(light.accent, accent);
    expect(dark.accent, accent);
    expect(light.onAccent, Colors.white);
    expect(dark.onAccent, Colors.white);
    expect(
      light.accentSubtle,
      Color.alphaBlend(accent.withValues(alpha: 0.14), light.surface),
    );
    expect(
      light.accentHover,
      Color.alphaBlend(accent.withValues(alpha: 0.20), light.surface),
    );
    expect(
      light.accentBorder,
      Color.alphaBlend(accent.withValues(alpha: 0.28), light.surface),
    );
    expect(
      light.accentPressed,
      Color.alphaBlend(accent.withValues(alpha: 0.28), light.surface),
    );
    expect(
      dark.accentSubtle,
      Color.alphaBlend(accent.withValues(alpha: 0.14), dark.surface),
    );
    expect(light.raisedContainer, const Color(0xFFE3DDCE));
    expect(dark.raisedContainer, const Color(0xFF2B3136));
    expect(light.error, const Color(0xFFD1495B));
    expect(dark.warning, const Color(0xFFE9B44C));
  });

  test('uses a black or white foreground for exact accent fills', () {
    expect(
      buildAliceColorTokens(testConfig(), Brightness.light).onAccent,
      Colors.white,
    );
    expect(
      buildAliceColorTokens(
        testConfig(accentColor: const Color(0xFFEEF4EE)),
        Brightness.dark,
      ).onAccent,
      Colors.black,
    );
  });

  testWidgets('projects Alice tokens into Material roles and control states', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      TopBarWorkspaceModule(
        workspaces: testWorkspaces(),
        onWorkspaceTap: (_) {},
      ),
    );

    final context = tester.element(find.byType(TopBarWorkspaceModule));
    final theme = Theme.of(context);
    final colors = AliceColorTokens.of(context);
    expect(theme.colorScheme.primary, colors.accent);
    expect(theme.colorScheme.primaryContainer, colors.accentSubtle);
    expect(theme.colorScheme.secondaryContainer, colors.raisedContainer);

    final inkWell = tester.widget<InkWell>(find.byType(InkWell).first);
    final overlay = inkWell.overlayColor!;
    expect(overlay.resolve({WidgetState.focused}), colors.accentFocus);
    expect(overlay.resolve({WidgetState.hovered}), colors.accentHover);
    expect(overlay.resolve({WidgetState.pressed}), colors.accentPressed);
  });
}
