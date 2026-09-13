## Context

The existing bar stream contains cached Rust state and Flutter isolates its network slice, but its Network panel is read-only route/nl80211 data. Panels use `AlicePanel`, a native panel-command bridge, `AliceSnapshotState`, and Flutter Rust Bridge (FRB) types. The runtime already owns long-lived cache services and triggers snapshot emissions without doing external I/O during snapshot construction.

This change adds an interactive Bluetooth surface. It must use `bluer`, and therefore BlueZ's system D-Bus API, while remaining absent when BlueZ or powered local hardware is absent. See proposal.md for motivation and the delta specs for observable behavior.

## Goals / Non-Goals

**Goals:**
- Keep BlueZ/D-Bus activity in a runtime-owned Bluetooth service and retain a snapshot-safe cache.
- Aggregate powered adapters while preserving stable, address-based device identity.
- Safely broker all requested BlueZ agent interactions through explicit Flutter prompts.
- Make scan, pair, trust, connect, and disconnect state visible, serialized per device, and testable without a live D-Bus service.

**Non-Goals:**
- Bluetooth radio power controls, adapter selection, forgetting/unpairing devices, file transfer, audio-profile configuration, or generic BlueZ settings.
- Wi-Fi changes or changing the existing Network panel.
- Supporting a second default BlueZ agent when BlueZ rejects Alice's exclusive default-agent request.
- Inferring physical proximity, signal quality, battery level, service compatibility, or successful audio/HID use from a connection flag.

## Decisions

### Use a dedicated `bluer` service and cache

Add a native Bluetooth module that owns a `bluer` session, watches BlueZ availability/adapters/devices, and writes a `BluetoothSnapshot` cache. The runtime starts this service independently from route networking and triggers bar emissions only after cache-visible changes. Snapshot assembly reads the cache synchronously through a provider seam.

`bluer` is selected because the requirement explicitly requires it and it exposes BlueZ device, adapter, discovery, and agent APIs in Rust. Direct `zbus` calls are rejected: they duplicate BlueZ protocol modeling and violate the chosen integration constraint. Dart-side D-Bus is rejected because native service lifecycle and pairing-agent ownership belong with the rest of Alice's system integrations.

### Model panel state separately from observed device state

`BarSnapshot` gains a Bluetooth slice containing availability, aggregated device records, scan state/results, per-device operation/error state, and at most one active BlueZ pairing or authorization prompt. A device record carries address identity, alias/name display candidates, connected/paired/trusted state, and class/appearance classification data. Flutter derives exclusive Connected, Known, and Nearby lists from this source state using address equality and the documented precedence.

This avoids treating a device's transient discovery observation as a new identity and avoids duplicate rows across adapters. A device's address is the native cache and UI key even if its user-facing label changes.

### Aggregate adapters and manage discovery ownership

The service observes every powered adapter. A scan atomically clears the retained nearby-result set, starts discovery on all then-powered adapters, and schedules its end for 15 seconds. It merges observations by address and stops only discovery sessions it started; results persist after completion until another scan starts. Adapter changes during a scan are reconciled without extending the fixed duration.

A single-adapter implementation was rejected because it ignores hardware chosen by the user. A UI adapter picker was rejected as unnecessary scope. Accumulating scan results indefinitely was rejected because stale observations would look current.

### Make pairing an explicit native-to-Flutter prompt protocol

Alice registers its agent and requests default-agent ownership while Bluetooth is available. Agent callbacks publish an opaque prompt token and await one FRB response from Flutter. Prompt variants cover PIN/passkey entry, passkey display, numeric confirmation, and device/service authorization; display-only prompts still expose cancellation. Flutter renders a modal within the Bluetooth panel, routes accept/deny/cancel responses through FRB, and never receives an agent object or D-Bus handle.

Only one prompt is active at a time; a concurrent request is denied/cancelled rather than ambiguously assigning a response. If Alice cannot obtain default-agent ownership, a pairing operation fails explicitly. Delegation to an existing desktop agent conflicts with the chosen ownership policy; auto-approving authorization conflicts with the requirement for explicit approval.

### Serialize per-device actions

A command service accepts FRB actions for scan, connect, disconnect, and responding to a pairing prompt. It serializes conflicting work per address. Connecting an unpaired device performs `pair`, then sets trusted, then `connect`; connecting a paired device skips pair/trust. The cache exposes the phase (`pairing`, `connecting`, `disconnecting`) and a retryable error on failure. Device-property changes reconcile the final state rather than assuming a successful D-Bus method call implies a completed connection.

Disconnect, trust changes, and all BlueZ mutation happen in the native command service, never from the snapshot provider. This preserves the existing no-I/O snapshot boundary.

### Integrate as a conditional standalone panel

Add `AlicePanel.bluetooth`, sizing, host binding, a Bluetooth `TopBarPanelTapTarget`, and a panel action callback chain from `AliceApp` through `AlicePlatform` to FRB. The Bluetooth control sits immediately before Network and is omitted rather than disabled when unavailable. The service reports unavailable when BlueZ is absent or no adapter is powered, allowing Flutter to close an already-open panel as the control vanishes.

Add semantic Alice icon descriptors for Bluetooth and common device categories. Class and LE appearance mapping is intentionally presentation-only, with a generic Bluetooth fallback rather than misleading unknown devices as a particular category.

### Test at cache and widget boundaries

Keep pure aggregation, list placement, label/icon selection, and Flutter snapshot/widget coverage testable in isolation. Flutter tests construct generated snapshot models and assert conditional top-bar placement, exclusive lists, scan retention, action state, and dialogs. Regenerate FRB bindings only after finalizing the Rust state/API contract.

Native Bluetooth command and agent behavior is validated manually against BlueZ; only Flutter automated tests exclude live BlueZ, a system D-Bus, Bluetooth hardware, discovery traffic, and pairing.

## Risks / Trade-offs

- [BlueZ agent registration/default ownership is rejected] → Surface a per-operation pairing error; do not silently delegate prompts or report false progress.
- [A malicious or noisy nearby device produces hostile names] → render bounded text, preserve address fallback, and avoid using raw names as identifiers.
- [Concurrent adapters report duplicate or inconsistent device properties] → key aggregation by address, apply deterministic preference rules, and let subsequent property updates reconcile the cache.
- [An adapter vanishes during discovery or an operation] → stop owned discovery where possible, cancel affected work, retain a retryable error, and recompute availability.
- [BlueZ method success precedes property propagation] → show in-progress state until observation confirms the resulting state or the operation errors/times out.
- [Default agent receives an unexpected pairing request] → require an active user-initiated operation before allowing a prompt; reject unsolicited requests.
- [FRB prompt response races with cancellation or service loss] → include opaque prompt tokens and make cancellation/idempotent late responses safe.

## Migration Plan

1. Add and compile-validate the pinned `bluer`/BlueZ integration, its service-availability lifecycle, and fake transport seams.
2. Add Bluetooth state and action/prompt API types, regenerate FRB bindings, and extend snapshot cache/provider aggregation.
3. Implement the native command and agent lifecycle; validate it manually against BlueZ.
4. Add the conditional bar control, standalone panel, prompt dialogs, and action wiring with Flutter tests.
5. Run Rust and Flutter suites without live BlueZ dependencies. Roll back by reverting the change; it creates no persistent Alice migration, though BlueZ pairing/trust changes made by explicit user action remain BlueZ state.
