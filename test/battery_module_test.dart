import 'package:alicebar/alice_config.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:alicebar/widgets/bar_widgets/battery_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('selects capacity bands and charging override', () {
    BatterySnapshot battery(int capacity, [String status = 'Discharging']) =>
        BatterySnapshot(capacity: capacity, status: status);
    expect(batteryIconFor(battery(10)), AliceIcons.batteryWarning);
    expect(batteryIconFor(battery(33)), AliceIcons.batteryLow);
    expect(batteryIconFor(battery(55)), AliceIcons.batteryMedium);
    expect(batteryIconFor(battery(77)), AliceIcons.batteryHigh);
    expect(batteryIconFor(battery(78)), AliceIcons.batteryFull);
    expect(batteryIconFor(battery(5, 'Charging')), AliceIcons.batteryCharging);
    expect(batteryIconFor(battery(100, 'Full')), AliceIcons.batteryCharging);
  });

  testWidgets('formats capacity and omits unavailable state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AliceIconTheme(
          config: AliceConfig.fallback(),
          child: const TopBarBatteryModule(
            battery: BatterySnapshot(capacity: 42, status: 'Discharging'),
          ),
        ),
      ),
    );
    expect(find.text('42%'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: AliceIconTheme(
          config: AliceConfig.fallback(),
          child: const TopBarBatteryModule(battery: null),
        ),
      ),
    );
    expect(find.text('42%'), findsNothing);
  });
}
