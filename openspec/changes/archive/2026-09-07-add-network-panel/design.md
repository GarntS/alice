## Context

The current provider scans `/sys/class/net`, treats `operstate` as a connected boolean, and runs `iw` to retrieve an SSID. It produces only `NetworkKind` and a label, while the Flutter control is a passive `TopBarPill`. Snapshot refresh currently uses a `notify` watcher on the sysfs directory. See proposal.md for motivation and the change specs for observable behavior.

The implementation must remain unprivileged and must not invoke network commands. Existing project dependencies include Tokio and `zbus`, but no route or Generic Netlink client. The Rust snapshot stream is bridged to Flutter and its generated bindings must be regenerated when state types change.

## Goals / Non-Goals

**Goals:**
- Collect route-link, route-address, and generic interface-counter state from an unprivileged process.
- Obtain current Wi-Fi association and SSID directly from nl80211's existing BSS cache, without triggering a scan.
- Present honest per-adapter and WireGuard information in a panel while preserving the lightweight bar icon.
- Keep network changes event-driven, with periodic counter polling and robust resynchronization.

**Non-Goals:**
- Connecting, disconnecting, scanning for, or configuring Wi-Fi networks.
- NetworkManager integration, commands/subprocesses, C/libnl FFI, capability changes, or privilege escalation.
- WireGuard peer status, endpoint, allowed IP, handshake, key, listening-port, or per-peer-counter collection.
- Claiming general Internet connectivity or WireGuard peer reachability from link state or generic counters.
- Rendering non-hardware virtual interfaces such as bridges, veths, taps, and container links in the adapter section.

## Decisions

### Use Rust-native route and nl80211 clients

Use `rtnetlink` for `NETLINK_ROUTE` dumps/subscriptions and `wl-nl80211` for Generic Netlink nl80211 requests, both on Tokio. Route state supplies interface identity, flags, `IFLA_OPERSTATE`, `IFLA_LINKINFO` kind, `IFLA_STATS64`, and addresses; nl80211 supplies Wi-Fi-interface identity and reads the existing BSS cache for association/SSID. `GET_SCAN` reads cached BSS data only and MUST NOT trigger a scan.

`iw` subprocesses are rejected because they violate the no-subprocess constraint. NetworkManager D-Bus is rejected because it makes Wi-Fi observability depend on a desktop daemon. Raw socket parsing and C/libnl FFI are rejected because the selected Rust crates provide the required protocol coverage with less local unsafe/protocol code.

An early compile-backed spike MUST validate the selected crate APIs, unprivileged `GET_SCAN` behavior, multipart dump completion, and relevant error mapping before the provider is migrated.

### Model observations separately

Replace the coarse label-oriented network snapshot with a bar-icon value plus adapter and WireGuard collections. Each interface record retains presence/identity, admin state, operational state, addresses, generic counters, and Wi-Fi association/SSID availability independently. Collection errors are represented distinctly from absent data and state values.

The UI selects the first IPv4 address when one is assigned; otherwise it selects IPv6; otherwise it displays no address. It does not need to display every retained address. SSID bytes are retained until presentation and invalid UTF-8 bytes are escaped as `\xNN`.

A single `usable` predicate for bar precedence is deliberately narrow: interface administrative state is up and it has either IPv4 or IPv6. Associated Wi-Fi with this predicate wins (`wifi-high`); another usable interface, including WireGuard, yields `network`; otherwise the presence of Wi-Fi hardware yields `wifi-x`; all other cases yield `network-x`.

### Classify panel interfaces conservatively

Exclude `lo`. Detect WireGuard by link kind and show it only in the dedicated section. Include WLAN adapters confirmed through nl80211 and conventional adapters whose `/sys/class/net/<name>/device` exists. The sysfs device link is used only as stable hardware-backing classification; route Netlink remains authoritative for dynamic state. Exclude remaining virtual interfaces to avoid noisy cards.

If nl80211 state cannot be obtained for a hardware-backed adapter, retain its card but show Wi-Fi classification/SSID availability honestly rather than removing it or inferring association.

### Keep WireGuard data unprivileged

Do not query WireGuard Generic Netlink. Generic route state, host addresses, and `IFLA_STATS64` are sufficient for the WireGuard card. Omit all peer-derived rows rather than displaying zero, disconnected, or unavailable values. `IFF_UP`, `operstate=unknown`, and generic counters must never be converted into peer-health claims.

### Synchronize and refresh safely

Subscribe to link, IPv4-address, and IPv6-address multicast groups before initial dumps, then reconcile notifications received during the dumps. Require a successful multipart completion, recognize interrupted dumps/overruns/connection loss, and resynchronize rather than treating incomplete results as empty state. Link/address notifications trigger semantic snapshot updates; periodic polling refreshes counters.

Request a 4 MiB receive buffer with unprivileged `SO_RCVBUF` on route and nl80211 sockets, accepting the kernel's `rmem_max` cap and retaining the effective size and any tuning error for diagnostics. Do not use `SO_RCVBUFFORCE`, change sysctls, or assume buffering prevents message loss.

Run each connection driver in an owned Tokio task. Supervise termination and unwind panics (including `netlink-proto 0.13.0`'s request-associated overrun panic), abort old drivers on cancellation, and reopen/resubscribe before fresh dumps. This strategy requires the default `panic=unwind`, not `panic=abort`. Forward `NLMSG_DONE` explicitly and validate its status plus `NLM_F_DUMP_INTR` through low-level request streams; EOF or ACK alone is not successful completion. Discard generations raced by notifications, and redump before publishing. Timeout stalled dumps after 10 seconds and delay reconnection retries by one second. Failed generations never become empty snapshots; consumers retain the last good snapshot and expose the error separately.

### Integrate as a standard Alice panel

Add `AlicePanel.network`, panel sizing, host binding to the granular network snapshot notifier, a new scrollable Network panel, and a `TopBarPanelTapTarget` around an icon-only network pill. Use the standard `PanelShell` title `Networks`, without adapter/WireGuard subheadings or empty WireGuard placeholders. Distinguish cards with Wi-Fi, network, or keyhole icons. Use a header row with icon, bold interface name, separator, and smaller administrative status; a middle row with an associated, non-empty Wi-Fi SSID or WireGuard RX/TX counters (omitted for missing SSIDs and other adapters; Wi-Fi diagnostics belong in the icon tooltip); and a final row with link icon/state and at icon/preferred address. Keep values on one visual line, with tooltips for full text and classification errors. An unavailable battery must not leave a zero-width slot consuming an extra gap in the top-bar wrap. Remove `show_network_label` through Rust config parsing/API mapping, Dart config, template, documentation, and tests. Regenerate Flutter Rust Bridge bindings after changing state/config types.

## Risks / Trade-offs

- [Unprivileged nl80211 access is denied or unsupported by a kernel/driver] → Preserve generic hardware adapter data and report Wi-Fi association/SSID as unavailable; do not fall back to commands or privilege.
- [Rust crate API/version assumptions differ from research] → Complete the explicit compile-backed Netlink spike before replacing the provider and pin compatible versions in Cargo.lock.
- [Multipart dumps race with notifications or are interrupted] → Subscribe before dumping, reconcile events, and resynchronize on interruption, overrun, or connection loss.
- [Interface classification misses unusual hardware or includes an unusual virtual link] → Centralize and unit-test the documented sysfs-plus-nl80211 rule; retain raw identity/state internally for diagnosis.
- [Per-second counter polling creates needless snapshot churn] → Publish only when the network snapshot changes and keep static/link state event-driven.
- [SSID bytes are hostile or non-text] → Escape non-UTF-8 bytes and constrain panel text layout; never log raw SSID bytes unnecessarily.

## Migration Plan

1. Add and validate route/nl80211 dependencies and collection seams while retaining hermetic fake-provider tests.
2. Migrate the snapshot model and regenerate Rust/Dart bridge bindings in one compatible change.
3. Replace the bar module/config mapping and add the panel; remove the label setting from the shipped template and documentation.
4. Verify Rust and Flutter tests, including no live network, Wi-Fi hardware, WireGuard, D-Bus, command, or elevated-privilege requirement.
5. Roll back by reverting the change; no persistent network-state migration or privileged service is introduced.
