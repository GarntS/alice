import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'helpers/alice_test_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('battery slice notifies independently and retains absence', () {
    final state = AliceSnapshotState(scheduleDateRollover: false);
    addTearDown(state.dispose);
    var batteryNotifications = 0;
    var workspaceNotifications = 0;
    state.battery.addListener(() => batteryNotifications++);
    state.workspaces.addListener(() => workspaceNotifications++);

    state.ingest(testSnapshot());
    state.ingest(
      testSnapshot(
        battery: const BatterySnapshot(capacity: 50, status: 'Discharging'),
      ),
    );
    state.ingest(
      testSnapshot(
        battery: const BatterySnapshot(capacity: 50, status: 'Discharging'),
      ),
    );
    state.ingest(testSnapshot());

    expect(batteryNotifications, 2);
    expect(workspaceNotifications, 1);
  });
}
