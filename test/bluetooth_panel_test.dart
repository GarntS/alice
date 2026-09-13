import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/bluetooth/prompt.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:alicebar/widgets/panels/bluetooth_panel.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

const _presentation = BluetoothDevicePresentation(
  category: BluetoothDeviceCategory.generic,
);

BluetoothDeviceSnapshot device(
  String address, {
  bool paired = false,
  bool connected = false,
}) => BluetoothDeviceSnapshot(
  address: address,
  alias: address == 'nearby' ? null : address,
  name: address == 'nearby' ? 'Nearby device' : null,
  paired: paired,
  trusted: paired,
  connected: connected,
  presentation: _presentation,
  operation: BluetoothOperationState.idle,
);

void main() {
  testWidgets('Bluetooth panel has exclusive lists and routes actions', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpAliceWidget(
      tester,
      BluetoothPanel(
        bluetooth: BluetoothSnapshot(
          available: true,
          devices: [
            device('connected', paired: true, connected: true),
            device('known', paired: true),
          ],
          scanState: BluetoothScanState.idle,
          scanResults: [
            device('connected', paired: true, connected: true),
            device('nearby'),
          ],
        ),
        onScan: () async => calls.add('scan'),
        onConnect: (address) async => calls.add('connect:$address'),
        onDisconnect: (address) async => calls.add('disconnect:$address'),
        onPromptResponse: (_, __) async {},
      ),
    );
    expect(find.text('Known Devices'), findsOneWidget);
    expect(find.text('Nearby Devices'), findsNothing);
    expect(
      find.byKey(const ValueKey('bluetooth-device-connected')),
      findsOneWidget,
    );
    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(find.text('Nearby Devices'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.tap(find.text('Connect').last);
    expect(
      calls,
      containsAll(<String>['scan', 'disconnect:connected', 'connect:nearby']),
    );
  });

  testWidgets('Bluetooth prompt submits explicit responses', (tester) async {
    PromptResponse? response;
    await pumpAliceWidget(
      tester,
      BluetoothPanel(
        bluetooth: const BluetoothSnapshot(
          available: true,
          devices: [],
          scanState: BluetoothScanState.idle,
          scanResults: [],
          prompt: BluetoothPrompt(
            token: 'token',
            address: 'AA',
            deviceLabel: 'Phone',
            kind: BluetoothPromptKind.requestConfirmation,
            passkey: 123456,
          ),
        ),
        onScan: () async {},
        onConnect: (_) async {},
        onDisconnect: (_) async {},
        onPromptResponse: (_, next) async => response = next,
      ),
    );
    expect(find.text('Passkey: 123456'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    expect(response, const PromptResponse.accept());
  });

  testWidgets(
    'top bar places available Bluetooth before network and hides it otherwise',
    (tester) async {
      final state = AliceSnapshotState(
        config: testConfig(),
        scheduleDateRollover: false,
      );
      addTearDown(state.dispose);
      final controller = PanelController();
      addTearDown(controller.dispose);
      final builds = <String>[];
      await pumpAliceWidget(
        tester,
        TopBar(
          config: testConfig(),
          snapshotState: state,
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
          onModuleBuild: builds.add,
        ),
      );
      state.ingest(testSnapshot());
      await tester.pump();
      expect(builds, isNot(contains('bluetooth')));
      builds.clear();
      state.ingest(
        testSnapshot(
          bluetooth: const BluetoothSnapshot(
            available: true,
            devices: [],
            scanState: BluetoothScanState.idle,
            scanResults: [],
          ),
        ),
      );
      await tester.pump();
      expect(builds.indexOf('bluetooth'), lessThan(builds.indexOf('network')));
    },
  );
}
