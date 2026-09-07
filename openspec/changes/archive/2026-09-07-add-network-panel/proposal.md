## Why

The network bar control currently exposes only a coarse state and optional text label, while its `/sys`- and `iw`-based provider cannot present per-adapter addresses or safely report unprivileged WireGuard state. Users need an icon-only entry point that explains the actual local network configuration without subprocesses or elevated privileges.

## What Changes

- Replace the network bar label with a clickable, icon-only control whose icon reflects usable Wi-Fi, other usable networking, Wi-Fi-only offline state, or no usable networking.
- Add a Network panel with one card for each hardware-backed Wi-Fi or Ethernet adapter, showing Wi-Fi network name when available, link state, and a preferred local address.
- Add a WireGuard section that shows only unprivileged, route-derived tunnel presence, state, host address, and generic traffic counters; do not expose peer data requiring `CAP_NET_ADMIN`.
- Replace `iw` subprocess collection with Rust Netlink collection for route/link/address state and nl80211 Wi-Fi association/SSID data.
- Remove the obsolete `network.show_label` configuration, defaults, documentation, generated mapping, and tests.

## Capabilities

### New Capabilities
- `network-panel`: Network panel interaction, adapter/WireGuard card rendering, and unprivileged status presentation.

### Modified Capabilities
- `network-status`: Network-state collection, icon precedence, refresh behavior, Wi-Fi detection, and removal of label behavior.
- `configuration`: Removal of the obsolete network label configuration field.
- `bar-shell-layout`: Network changes from a passive labeled pill to a panel-opening icon-only control.

## Impact

- Rust network provider, snapshot types, Flutter Rust Bridge-generated bindings, and snapshot state.
- Flutter top-bar network module, panel controller/host/sizing, and new network panel widgets.
- Native dependencies for Rust route Netlink and nl80211 support.
- Default configuration, README/design documentation, and Rust/Flutter tests.
