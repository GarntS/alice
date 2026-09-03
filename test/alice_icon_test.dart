import 'package:alicebar/widgets/alice_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  testWidgets('renders regular icons when duotone is disabled', (tester) async {
    await pumpAliceWidget(
      tester,
      const AliceIcon(AliceIcons.sun, color: Color(0xFF112233)),
      config: testConfig(useDuotoneIcons: false),
    );

    expect(find.byType(PhosphorIcon), findsNothing);
    expect(find.byIcon(AliceIcons.sun.regular), findsOneWidget);
  });

  testWidgets('uses accent for the duotone secondary layer', (tester) async {
    final config = testConfig();
    await pumpAliceWidget(
      tester,
      const AliceIcon(AliceIcons.sun),
      config: config,
    );

    final icon = tester.widget<PhosphorIcon>(find.byType(PhosphorIcon));
    expect(icon.duotoneSecondaryColor, config.accentColor);
  });

  testWidgets('uses brightness-aware gray and preserves primary color', (
    tester,
  ) async {
    const primary = Color(0xFFD1495B);
    await pumpAliceWidget(
      tester,
      const AliceIcon(AliceIcons.warningCircle, color: primary),
      config: testConfig(useAccentOnIcons: false),
    );

    var icon = tester.widget<PhosphorIcon>(find.byType(PhosphorIcon));
    expect(icon.color, primary);
    expect(icon.duotoneSecondaryColor, const Color(0xFF6B7280));

    await pumpAliceWidget(
      tester,
      const AliceIcon(AliceIcons.warningCircle, color: primary),
      config: testConfig(useAccentOnIcons: false),
      brightness: Brightness.dark,
    );
    icon = tester.widget<PhosphorIcon>(find.byType(PhosphorIcon));
    expect(icon.duotoneSecondaryColor, const Color(0xFF9CA3AF));
  });
}
