import 'package:alicebar/panel_controller.dart';
import 'package:alicebar/rust_gen/state.dart';
import 'package:alicebar/snapshot_state.dart';
import 'package:alicebar/widgets/alice_icon.dart';
import 'package:alicebar/widgets/bar_widgets/network_module.dart';
import 'package:alicebar/widgets/bar_widgets/cpu_module.dart';
import 'package:alicebar/widgets/bar_widgets/battery_module.dart';
import 'package:alicebar/widgets/panels/panel_shell.dart';
import 'package:alicebar/widgets/bar_widgets/pill.dart';
import 'package:alicebar/widgets/panels/network_panel.dart';
import 'package:alicebar/widgets/panels/panel_host.dart';
import 'package:alicebar/widgets/panels/panel_sizes.dart';
import 'package:alicebar/widgets/top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/alice_test_helpers.dart';

NetworkInterfaceSnapshot interface({
  int index = 2,
  String name = 'wlan0',
  List<String>? addresses,
  WifiSnapshot? wifi,
  bool wireguard = false,
  BigInt? rxBytes,
  String? classificationError,
  bool adminUp = true,
  String? operationalState = 'unknown',
}) {
  final ips = addresses ?? ['fd00::2', '192.0.2.2'];
  return NetworkInterfaceSnapshot(
    index: index,
    name: name,
    flags: 1,
    adminUp: adminUp,
    operationalState: operationalState,
    linkKind: wireguard ? 'wireguard' : null,
    hardwareBacked: !wireguard,
    addresses: ips,
    preferredAddress:
        ips.where((ip) => !ip.contains(':')).firstOrNull ?? ips.firstOrNull,
    rxBytes: rxBytes,
    txBytes: wireguard ? BigInt.from(456) : null,
    wifi: wifi,
    classificationError: classificationError,
  );
}

NetworkSnapshot network({
  List<NetworkInterfaceSnapshot>? adapters,
  List<NetworkInterfaceSnapshot> wireguard = const [],
  String? error,
}) => NetworkSnapshot(
  kind: NetworkKind.wifi,
  adapters: adapters ?? [interface()],
  wireguard: wireguard,
  error: error,
);

void main() {
  testWidgets('all network states are icon-only and selectable', (
    tester,
  ) async {
    const icons = {
      NetworkKind.wifi: AliceIcons.wifi,
      NetworkKind.wired: AliceIcons.ethernet,
      NetworkKind.wifiDisconnected: AliceIcons.wifiDisconnected,
      NetworkKind.disconnected: AliceIcons.networkSlash,
    };
    var taps = 0;
    for (final entry in icons.entries) {
      await pumpAliceWidget(
        tester,
        TopBarNetworkModule(networkKind: entry.key, onToggle: (_) => taps++),
      );
      final module = find.byType(TopBarNetworkModule);
      expect(
        find.descendant(of: module, matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        tester.widget<TopBarPill>(find.byType(TopBarPill)).icon,
        entry.value,
      );
      await tester.tap(module);
    }
    expect(taps, 4);
  });

  testWidgets('top bar toggles and highlights only its network control', (
    tester,
  ) async {
    final controller = PanelController();
    final state = testSnapshotState(snapshot: testSnapshot());
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    final builds = <String, int>{};
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1300,
        height: 80,
        child: TopBar(
          config: testConfig(),
          snapshotState: state,
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
          onModuleBuild: (name) => builds[name] = (builds[name] ?? 0) + 1,
        ),
      ),
      size: const Size(1500, 140),
    );
    builds.clear();
    await tester.tap(find.byType(TopBarNetworkModule));
    await tester.pump();
    expect(controller.openPanel, AlicePanel.network);
    expect(
      tester
          .widget<TopBarNetworkModule>(find.byType(TopBarNetworkModule))
          .highlighted,
      isTrue,
    );
    expect(builds, {'network': 1});
    await tester.tap(find.byType(TopBarNetworkModule));
    await tester.pump();
    expect(controller.openPanel, isNull);
    expect(
      tester
          .widget<TopBarNetworkModule>(find.byType(TopBarNetworkModule))
          .highlighted,
      isFalse,
    );
    builds.clear();
    state.ingest(copyTestSnapshot(state.currentSnapshot, network: network()));
    await tester.pump();
    expect(builds, {'network': 1});
    expectNoFlutterErrors();
  });

  testWidgets('absent battery does not leave an extra gap before network', (
    tester,
  ) async {
    final controller = PanelController();
    final state = testSnapshotState(snapshot: testSnapshot());
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 1300,
        height: 80,
        child: TopBar(
          config: testConfig(),
          snapshotState: state,
          panelController: controller,
          onWorkspaceTap: (_) {},
          onTrayItemTap: (_) {},
          onBackgroundTap: () {},
        ),
      ),
      size: const Size(1500, 140),
    );
    final cpu = find.byType(TopBarCpuModule);
    final network = find.byType(TopBarNetworkModule);
    expect(find.byType(TopBarBatteryModule), findsNothing);
    expect(tester.getTopLeft(network).dx - tester.getTopRight(cpu).dx, 8);
    state.ingest(
      testSnapshot(
        battery: const BatterySnapshot(capacity: 80, status: 'Discharging'),
      ),
    );
    await tester.pump();
    final battery = find.byType(TopBarBatteryModule);
    expect(tester.getTopLeft(battery).dx - tester.getTopRight(cpu).dx, 8);
    expect(tester.getTopLeft(network).dx - tester.getTopRight(battery).dx, 8);
    state.ingest(testSnapshot());
    await tester.pump();
    expect(find.byType(TopBarBatteryModule), findsNothing);
    expect(tester.getTopLeft(network).dx - tester.getTopRight(cpu).dx, 8);
    expectNoFlutterErrors();
  });

  testWidgets(
    'Networks uses the shared title and icon cards without section headings',
    (tester) async {
      await pumpAliceWidget(
        tester,
        SizedBox(
          width: 380,
          height: 600,
          child: NetworkPanel(
            network: network(
              adapters: [
                interface(
                  wifi: const WifiSnapshot(
                    association: WifiAssociation.notAssociated,
                  ),
                ),
                interface(index: 3, name: 'eth0'),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.widget<PanelShell>(find.byType(PanelShell)).title,
        'Networks',
      );
      expect(find.text('Networks'), findsOneWidget);
      for (final title in [
        'Network',
        'Adapters',
        'WireGuard',
        'No WireGuard interfaces',
      ]) {
        expect(find.text(title), findsNothing);
      }
      for (final (index, icon) in [
        (2, AliceIcons.wifi),
        (3, AliceIcons.ethernet),
      ]) {
        final card = find.byKey(ValueKey('network-interface-$index'));
        expect(
          tester
              .widget<AliceIcon>(
                find
                    .descendant(of: card, matching: find.byType(AliceIcon))
                    .first,
              )
              .icon,
          icon,
        );
      }
      final name = tester.widget<Text>(find.text('wlan0'));
      final address = tester.widget<Text>(find.text('192.0.2.2').first);
      final admin = tester.widget<Text>(find.text('Up').first);
      expect(name.style!.fontSize, greaterThan(address.style!.fontSize!));
      expect(name.style!.fontWeight, FontWeight.w700);
      expect(admin.style!.fontSize, lessThan(address.style!.fontSize!));
      expect(address.style!.fontWeight, FontWeight.w600);
      expect(find.byKey(const ValueKey('network-middle-3')), findsNothing);
      expectNoFlutterErrors();
    },
  );

  testWidgets(
    'adapter cards show escaped SSID, preferred host address, and unavailable state',
    (tester) async {
      for (final (ips, expected) in [
        (['fd00::2', '192.0.2.2'], '192.0.2.2'),
        (['fd00::2'], 'fd00::2'),
        (<String>[], 'No address assigned'),
      ]) {
        await pumpAliceWidget(
          tester,
          SizedBox(
            width: 380,
            height: 600,
            child: NetworkPanel(
              network: network(
                adapters: [
                  interface(
                    addresses: ips,
                    wifi: const WifiSnapshot(
                      association: WifiAssociation.associated,
                      ssid: r'café\xFF',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text(r'café\xFF'), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        expect(find.text('Up'), findsOneWidget);
      }
      for (final (wifi, expected) in [
        (
          const WifiSnapshot(
            association: WifiAssociation.unavailable,
            unavailableReason: 'No cached BSS data',
          ),
          'Unavailable: No cached BSS data',
        ),
        (
          const WifiSnapshot(association: WifiAssociation.associated, ssid: ''),
          'SSID unavailable: No network name',
        ),
        (
          const WifiSnapshot(
            association: WifiAssociation.unavailable,
            unavailableReason: 'Permission denied',
          ),
          'Unavailable: Permission denied',
        ),
        (
          const WifiSnapshot(association: WifiAssociation.notAssociated),
          'Not associated',
        ),
        (
          const WifiSnapshot(
            association: WifiAssociation.associated,
            unavailableReason: 'Data absent',
          ),
          'SSID unavailable: Data absent',
        ),
      ]) {
        await pumpAliceWidget(
          tester,
          SizedBox(
            width: 380,
            height: 600,
            child: NetworkPanel(
              network: network(
                adapters: [
                  interface(
                    wifi: wifi,
                    adminUp: false,
                    operationalState: 'down',
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text(expected), findsNothing);
        expect(find.byKey(const ValueKey('network-middle-2')), findsNothing);
        expect(find.byTooltip('Wi-Fi: $expected'), findsOneWidget);
        expect(find.text('Down'), findsNWidgets(2));
      }
      expectNoFlutterErrors();
    },
  );

  testWidgets('cards use the requested row order and constrain long values', (
    tester,
  ) async {
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 380,
        height: 600,
        child: NetworkPanel(
          network: network(
            adapters: [
              interface(
                operationalState: 'down',
                wifi: const WifiSnapshot(
                  association: WifiAssociation.associated,
                  ssid: 'The LAN Before Time',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final header = find.byKey(const ValueKey('network-header-2'));
    final middle = find.byKey(const ValueKey('network-middle-2'));
    final footer = find.byKey(const ValueKey('network-link-2'));
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: header, matching: find.byType(Text)),
          )
          .map((text) => text.data),
      ['wlan0', ' - ', 'Up'],
    );
    expect(tester.widget<Text>(middle).data, 'The LAN Before Time');
    expect(
      tester
          .widgetList<AliceIcon>(
            find.descendant(of: footer, matching: find.byType(AliceIcon)),
          )
          .map((icon) => icon.icon),
      [AliceIcons.link, AliceIcons.at],
    );
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: footer, matching: find.byType(Text)),
          )
          .map((text) => text.data),
      ['Down', '192.0.2.2'],
    );
    expect(
      tester.getBottomLeft(header).dy,
      lessThan(tester.getTopLeft(middle).dy),
    );
    expect(
      tester.getBottomLeft(middle).dy,
      lessThan(tester.getTopLeft(footer).dy),
    );
    await pumpAliceWidget(
      tester,
      SizedBox(
        width: 220,
        height: 600,
        child: NetworkPanel(
          network: network(
            adapters: [
              interface(
                name: 'a-very-long-interface-name',
                adminUp: false,
                operationalState: null,
                addresses: ['2001:db8:1234:5678:9012:3456:7890:abcd'],
                wifi: const WifiSnapshot(
                  association: WifiAssociation.associated,
                  ssid: 'A very long wireless network name',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(tester.widget<Text>(middle).maxLines, 1);
    expect(tester.widget<Text>(middle).overflow, TextOverflow.ellipsis);
    expectNoFlutterErrors();
  });

  testWidgets(
    'WireGuard cards exclude peer data and show only generic counters',
    (tester) async {
      await pumpAliceWidget(
        tester,
        SizedBox(
          width: 380,
          height: 600,
          child: NetworkPanel(
            network: network(
              adapters: [],
              wireguard: [
                interface(
                  index: 5,
                  name: 'wg0',
                  wireguard: true,
                  addresses: ['10.0.0.1'],
                  rxBytes: BigInt.from(123),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.widget<AliceIcon>(find.byType(AliceIcon).first).icon,
        AliceIcons.keyhole,
      );
      expect(find.text('WireGuard'), findsNothing);
      expect(find.text('No hardware adapters'), findsNothing);
      for (final text in [
        'wg0',
        '10.0.0.1',
        'RX 123 B · TX 456 B',
        'Unknown',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      for (final word in [
        'Peer',
        'Endpoint',
        'Handshake',
        'Key',
        'Port',
        'Connected',
      ]) {
        expect(find.textContaining(word), findsNothing);
      }
      expectNoFlutterErrors();
    },
  );

  testWidgets(
    'panel host is bound to network updates and long content scrolls',
    (tester) async {
      final state = testSnapshotState(
        snapshot: testSnapshot(network: network()),
      );
      addTearDown(state.dispose);
      expect(alicePanelSize(AlicePanel.network), const Size(380, 600));
      await pumpAliceWidget(
        tester,
        AlicePanelCard(
          panel: AlicePanel.network,
          config: testConfig(),
          snapshotState: state,
          onPowerAction: (_) async {},
          onMediaAction: (_) async {},
          onSeekMedia: (_) async {},
          onTrayAction: (_) async {},
          onDismissNotification: (_) async {},
          onDismissAllNotifications: () async {},
          onMarkAllNotificationsRead: () async {},
          onInvokeNotificationAction: (_, __) async {},
        ),
        size: const Size(450, 700),
      );
      state.ingest(
        copyTestSnapshot(
          state.currentSnapshot,
          network: network(
            adapters: [
              for (var i = 2; i < 16; i++)
                interface(
                  index: i,
                  name: 'ethernet-$i',
                  classificationError: 'Unsupported',
                ),
            ],
            error: 'Snapshot stale',
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Network information unavailable: Snapshot stale'),
        findsOneWidget,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(find.text('ethernet-15').hitTestable(), findsOneWidget);
      expectNoFlutterErrors();
    },
  );

  test('network state deeply freezes lists and compares full observations', () {
    final state = AliceSnapshotState(scheduleDateRollover: false);
    addTearDown(state.dispose);
    final ips = ['192.0.2.2'];
    final adapters = [interface(addresses: ips)];
    final tunnels = [
      interface(index: 5, name: 'wg0', wireguard: true, rxBytes: BigInt.one),
    ];
    state.ingest(
      testSnapshot(
        network: network(adapters: adapters, wireguard: tunnels),
      ),
    );
    var notifications = 0;
    state.network.addListener(() => notifications++);
    ips.clear();
    adapters.clear();
    tunnels.clear();
    expect(state.currentNetwork.adapters.single.addresses, ['192.0.2.2']);
    expect(state.currentNetwork.wireguard, hasLength(1));
    expect(() => state.currentNetwork.adapters.clear(), throwsUnsupportedError);
    expect(
      () => state.currentNetwork.adapters.single.addresses.clear(),
      throwsUnsupportedError,
    );
    final equivalent = network(
      adapters: [
        interface(addresses: ['192.0.2.2']),
      ],
      wireguard: [
        interface(index: 5, name: 'wg0', wireguard: true, rxBytes: BigInt.one),
      ],
    );
    state.ingest(testSnapshot(network: equivalent));
    expect(notifications, 0);
    state.ingest(
      testSnapshot(
        network: network(
          adapters: equivalent.adapters,
          wireguard: [
            interface(
              index: 5,
              name: 'wg0',
              wireguard: true,
              rxBytes: BigInt.two,
            ),
          ],
        ),
      ),
    );
    expect(notifications, 1);
    state.ingest(
      testSnapshot(
        network: network(
          adapters: equivalent.adapters,
          wireguard: state.currentNetwork.wireguard,
          error: 'Interrupted',
        ),
      ),
    );
    expect(notifications, 2);
  });
}
