import 'package:flutter_test/flutter_test.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';

void main() {
  TrayItemSnapshot item({
    bool menuOnly = false,
    TrayCapability activate = TrayCapability.unknown,
    String? status = 'Active',
    String? menuPath,
  }) => TrayItemSnapshot(
    id: 'one',
    label: 'One',
    serviceName: 'org.example.One',
    objectPath: '/Item',
    iconPngBytes: null,
    status: status,
    itemIsMenu: menuOnly,
    menuPath: menuPath,
    activate: activate,
    secondaryActivate: TrayCapability.unsupported,
    contextMenu: TrayCapability.unsupported,
  );
  test('tray comparisons include action and menu metadata', () {
    final base = item();
    expect(trayItemSnapshotsEqual(base, item()), isTrue);
    expect(trayItemSnapshotsEqual(base, item(menuOnly: true)), isFalse);
    expect(
      trayItemSnapshotsEqual(base, item(activate: TrayCapability.supported)),
      isFalse,
    );
    expect(
      trayItemSnapshotsEqual(base, item(status: 'NeedsAttention')),
      isFalse,
    );
    expect(trayItemSnapshotsEqual(base, item(menuPath: '/Menu')), isFalse);
  });
}
