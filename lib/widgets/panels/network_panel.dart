import 'package:material_ui/material_ui.dart';

import '../../alice_theme.dart';
import '../../rust_gen/state.dart';
import '../alice_icon.dart';
import 'panel_shell.dart';

class NetworkPanel extends StatelessWidget {
  const NetworkPanel({super.key, required this.network});

  final NetworkSnapshot network;

  @override
  Widget build(BuildContext context) => PanelShell(
    title: 'Networks',
    crossAxisAlignment: CrossAxisAlignment.stretch,
    child: Flexible(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (network.error case final error?) ...[
              Text(
                'Network information unavailable: $error',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],
            if (network.adapters.isEmpty && network.wireguard.isEmpty)
              const Text('No network interfaces'),
            for (final adapter in network.adapters)
              _InterfaceCard(interface: adapter),
            for (final tunnel in network.wireguard)
              _InterfaceCard(interface: tunnel, wireguard: true),
          ],
        ),
      ),
    ),
  );
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({required this.interface, this.wireguard = false});

  final NetworkInterfaceSnapshot interface;
  final bool wireguard;

  @override
  Widget build(BuildContext context) {
    final wifi = interface.wifi;
    final theme = Theme.of(context);
    final icon = wireguard
        ? AliceIcons.keyhole
        : wifi != null
        ? AliceIcons.wifi
        : AliceIcons.ethernet;
    final address = interface.preferredAddress ?? 'No address assigned';
    final rawState = interface.operationalState;
    final linkState = rawState == null || rawState.isEmpty
        ? 'Unavailable'
        : '${rawState[0].toUpperCase()}${rawState.substring(1)}';
    final secondary = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ssid = wifi?.association == WifiAssociation.associated
        ? wifi?.ssid
        : null;
    final middle = wireguard
        ? 'RX ${_traffic(interface.rxBytes)} · TX ${_traffic(interface.txBytes)}'
        : ssid != null && ssid.isNotEmpty
        ? ssid
        : null;
    final wifiDiagnostic = wifi == null
        ? null
        : switch (wifi.association) {
            WifiAssociation.associated =>
              middle == null
                  ? 'SSID unavailable: ${wifi.unavailableReason ?? "No network name"}'
                  : null,
            WifiAssociation.notAssociated => 'Not associated',
            WifiAssociation.unavailable =>
              'Unavailable: ${wifi.unavailableReason ?? "Data absent"}',
          };

    return Container(
      key: ValueKey('network-interface-${interface.index}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AliceColorTokens.of(context).raisedContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: ValueKey('network-header-${interface.index}'),
            children: [
              Tooltip(
                message: interface.classificationError == null
                    ? wireguard
                          ? 'WireGuard'
                          : wifi != null
                          ? wifiDiagnostic == null
                                ? 'Wi-Fi'
                                : 'Wi-Fi: $wifiDiagnostic'
                          : 'Network adapter'
                    : 'Wi-Fi classification unavailable: ${interface.classificationError}',
                child: AliceIcon(icon, size: 20),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Tooltip(
                  message: interface.name,
                  child: Text(
                    interface.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Text(' - ', style: secondary),
              Tooltip(
                message: 'Administrative state',
                child: Text(
                  interface.adminUp ? 'Up' : 'Down',
                  style: secondary,
                ),
              ),
            ],
          ),
          if (middle != null) ...[
            const SizedBox(height: 8),
            Tooltip(
              message: middle,
              child: Text(
                middle,
                key: ValueKey('network-middle-${interface.index}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            key: ValueKey('network-link-${interface.index}'),
            children: [
              const AliceIcon(
                AliceIcons.link,
                size: 14,
                semanticLabel: 'Link state',
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Tooltip(
                  message: 'Link state: $linkState',
                  child: Text(
                    linkState,
                    style: secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const AliceIcon(
                AliceIcons.at,
                size: 14,
                semanticLabel: 'IP address',
              ),
              const SizedBox(width: 5),
              Expanded(
                flex: 3,
                child: Tooltip(
                  message: address,
                  child: Text(
                    address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _traffic(BigInt? bytes) => bytes == null ? 'Unavailable' : '$bytes B';
}
