## Why

Alice has no way to discover, pair, connect, or disconnect Bluetooth devices. Users need an optional, native Bluetooth control surface that appears only when BlueZ and usable hardware are available, without relying on an external desktop network manager.

## What Changes

- Add a dedicated Bluetooth top-bar control and panel, visible only while the BlueZ service is available and at least one Bluetooth adapter is powered.
- Collect and control Bluetooth state through Rust's `bluer` library and BlueZ: aggregate all powered adapters; list connected devices, paired-but-disconnected known devices, and nearby scan results.
- Add a 15-second all-adapter scan that retains its merged results until the next scan; label devices by alias, advertised name, then address, and render a class/appearance-based icon with a generic fallback.
- Allow connection to known devices; allow scanned devices to pair, become trusted, and connect; allow connected devices to disconnect.
- Register Alice as BlueZ's default pairing agent and present PIN/passkey, numeric-confirmation, and service/device-authorization prompts, with per-device operation progress and retryable errors.
- Extend the native-to-Flutter snapshot stream and panel action APIs while preserving hermetic tests without live BlueZ hardware or D-Bus.

## Capabilities

### New Capabilities
- `bluetooth-device-management`: BlueZ-backed Bluetooth service lifecycle, discovery, device presentation, pairing authorization, and connect/disconnect behavior in Alice's dedicated panel.

### Modified Capabilities
- `bar-shell-layout`: Add the conditional Bluetooth top-bar control and its panel-opening behavior.
- `snapshot-state`: Publish and isolate Bluetooth snapshot updates alongside the existing granular state slices.
- `snapshot-runtime`: Include cached Bluetooth state in bar snapshots without performing Bluetooth/D-Bus work during snapshot assembly.

## Impact

- Rust: new Bluetooth service/state module, runtime lifecycle, `flutter_rust_bridge` API and generated bindings, and a new `bluer` dependency backed by BlueZ.
- Flutter: top-bar module, panel controller/host/sizing, Bluetooth panel, pairing/authorization dialogs, action wiring, icons, and snapshot comparison/freezing.
- Tests: Flutter widget/state tests must not require BlueZ, D-Bus, a Bluetooth adapter, or nearby devices. Native Bluetooth behavior is validated manually against BlueZ.
