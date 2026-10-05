import 'dart:async';

import 'package:alicebar/app.dart';
import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/api.dart' as frb;
import 'package:alicebar/snapshot_state.dart';
import 'package:alicebar/widgets/panels/media_panel.dart';
import 'package:alicebar/widgets/panels/panel_host.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/alice_test_helpers.dart';

void main() {
  test('a stale native hide cannot clear a newer popup request', () {
    final map = <int, String>{7: 'trayMenu'};
    const hide = frb.PanelCommand(
      requestId: 1,
      visible: false,
      panelId: 'trayOverflow',
      viewId: 7,
      includeIconBytes: false,
      anchorX: 0,
      anchorY: 0,
      width: 0,
      height: 0,
    );
    expect(
      applyPanelCommandToViewMap(map, hide, expectedRequestId: 2),
      isFalse,
    );
    expect(map, {7: 'trayMenu'});
    const current = frb.PanelCommand(
      requestId: 2,
      visible: false,
      panelId: 'trayMenu',
      viewId: 7,
      includeIconBytes: false,
      anchorX: 0,
      anchorY: 0,
      width: 0,
      height: 0,
    );
    expect(
      applyPanelCommandToViewMap(map, current, expectedRequestId: 2),
      isTrue,
    );
    expect(map, isEmpty);
  });
  testWidgets('null panel command unmounts previously rendered panel widgets', (
    tester,
  ) async {
    final commands = StreamController<frb.PanelCommand?>.broadcast(sync: true);
    final snapshotState = testSnapshotState();
    var disposedPanelSubtrees = 0;
    addTearDown(commands.close);
    addTearDown(snapshotState.dispose);

    await pumpAliceWidget(
      tester,
      _PanelCommandRenderHarness(
        commands: commands.stream,
        snapshotState: snapshotState,
        onPanelSubtreeDisposed: () => disposedPanelSubtrees++,
      ),
    );

    commands.add(
      const frb.PanelCommand(
        panelId: 'media',
        requestId: 1,
        visible: true,
        viewId: 7,
        includeIconBytes: false,
        anchorX: 0,
        anchorY: 0,
        width: 360,
        height: 228,
      ),
    );
    await tester.pump();

    expect(find.byType(MediaPanel), findsOneWidget);
    expect(find.textContaining('A Very Testable Song'), findsOneWidget);
    expect(disposedPanelSubtrees, 0);

    commands.add(null);
    await tester.pump();

    expect(find.byType(MediaPanel), findsNothing);
    expect(find.textContaining('A Very Testable Song'), findsNothing);
    expect(disposedPanelSubtrees, 1);
  });
}

class _PanelCommandRenderHarness extends StatefulWidget {
  const _PanelCommandRenderHarness({
    required this.commands,
    required this.snapshotState,
    required this.onPanelSubtreeDisposed,
  });

  final Stream<frb.PanelCommand?> commands;
  final AliceSnapshotState snapshotState;
  final VoidCallback onPanelSubtreeDisposed;

  @override
  State<_PanelCommandRenderHarness> createState() =>
      _PanelCommandRenderHarnessState();
}

class _PanelCommandRenderHarnessState
    extends State<_PanelCommandRenderHarness> {
  final Map<int, String> _viewPanelMap = <int, String>{};
  late final StreamSubscription<frb.PanelCommand?> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.commands.listen((command) {
      setState(() => applyPanelCommandToViewMap(_viewPanelMap, command));
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = alicePanelFromId(_viewPanelMap[7]);
    if (panel == null) return const SizedBox.shrink();

    return _DisposeProbe(
      onDispose: widget.onPanelSubtreeDisposed,
      child: AlicePanelCard(
        panel: panel,
        config: testConfig(),
        snapshotState: widget.snapshotState,
        onPowerAction: (_) async {},
        onMediaAction: (_) async {},
        onSeekMedia: (_) async {},
        onTrayAction: (_) async {},
        onDismissNotification: (_) async {},
        onDismissAllNotifications: () async {},
        onMarkAllNotificationsRead: () async {},
        onInvokeNotificationAction: (_, __) async {},
      ),
    );
  }
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
