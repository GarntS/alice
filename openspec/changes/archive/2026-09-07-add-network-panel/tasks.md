## 1. Netlink collection foundation

- [x] 1.1 Add and pin Rust-native `rtnetlink` and `wl-nl80211` dependencies compatible with the project's Tokio runtime.
- [x] 1.2 Build a compile-backed, hermetic collection seam that validates route dumps/subscriptions, nl80211 family access, multipart completion/error handling, and unprivileged cached-BSS lookup without commands or capabilities.
- [x] 1.3 Implement route-link and route-address collection for non-loopback interfaces, including flags, operational state, link kind, hardware-backing classification, generic counters, and IPv4/IPv6 addresses.
- [x] 1.4 Implement nl80211 Wi-Fi interface classification and cached-BSS association/SSID lookup with bounds-checked information-element parsing and byte-safe SSID representation.
- [x] 1.5 Implement link/address event subscriptions, periodic counter refresh, notification/dump reconciliation, and resynchronization after interrupted dumps, overrun, or connection loss.

### Foundation progress notes

- Added `native/alice_platform/src/network/transport.rs`: best-effort 4 MiB receive buffers for route/nl80211, subscribed route sessions, explicit multipart completion validation, read-only link/address/interface/cached-BSS dump requests, and supervised reconnect/redump after overrun, interruption, timeout, termination, or driver panic.
- Transport and classification tests pass. The runtime now uses independent supervised route/nl80211 workers and a cached provider. The old sysfs/inotify watcher and `iw` command path are removed; strict all-target Clippy passes.

## 2. Network snapshot and native integration

- [x] 2.1 Replace the coarse network snapshot model with icon state plus adapter and WireGuard records that preserve state, unavailable-data reasons, preferred address, and generic traffic separately.
- [x] 2.2 Implement hardware adapter and WireGuard classification, bar-icon precedence, IPv4-then-IPv6 selection, and the unprivileged WireGuard-data boundary.
- [x] 2.3 Migrate the network provider/runtime watcher to the Netlink-backed implementation and preserve provider-failure fallbacks.
- [x] 2.4 Regenerate Flutter Rust Bridge bindings and update Dart snapshot-state equality, freezing, and granular network notification handling for the expanded model.
- [x] 2.5 Add hermetic Rust tests for icon precedence, classification, address selection, SSID escaping, unavailable/error distinctions, and WireGuard peer-data exclusion.

## 3. Network panel UI

- [x] 3.1 Add the Network panel identity, open-state notifier, sizing, panel-host binding, and icon-only clickable top-bar network control.
- [x] 3.2 Implement a scrollable Network panel with hardware adapter cards showing name, Wi-Fi network-name availability, link state, and preferred address.
- [x] 3.3 Implement WireGuard cards showing only name, administrative/operational state, preferred host address, and generic RX/TX counters.
- [x] 3.4 Add Flutter widget/snapshot tests for icon-only rendering, panel toggling/highlighting, adapter and WireGuard content, IPv4/IPv6 display selection, unavailable Wi-Fi state, and escaped SSID text.

## 4. Remove network-label configuration

- [x] 4.1 Remove `network.show_label` from Rust configuration types/parsing/defaults, Flutter configuration mapping, and generated bindings.
- [x] 4.2 Remove the setting from the shipped default configuration, README, and design documentation.
- [x] 4.3 Update configuration and top-bar tests to remove label behavior and verify icon-only network presentation.

## 5. Verification

- [x] 5.1 Run Rust formatting, linting, and hermetic native tests.
- [x] 5.2 Regenerate/check Flutter bindings, format Dart, and run the Flutter test suite without requiring live interfaces, Wi-Fi hardware, WireGuard, D-Bus, commands, or elevated privileges.
- [x] 5.3 Validate the completed OpenSpec change with strict validation.
