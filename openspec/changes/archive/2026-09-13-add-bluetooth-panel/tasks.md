## 1. Native Bluetooth foundations

- [x] 1.1 Add and compile-validate the pinned `bluer` dependency and create Bluetooth transport, cache, and fake-transport seams without requiring live BlueZ.
- [x] 1.2 Define Bluetooth snapshot models for availability, address-identified devices, class/appearance presentation data, scan state/results, operations/errors, and pairing/authorization prompts.
- [x] 1.3 Implement pure aggregation, label fallback, class/appearance fallback, exclusive list precedence, and deep equality tests for multi-adapter observations.
- [x] 1.4 Implement BlueZ service/adaptor/device lifecycle monitoring that exposes Bluetooth only when BlueZ is present and at least one adapter is powered.
- [x] 1.5 Integrate the cached Bluetooth provider into runtime startup, triggers, snapshot assembly, failure fallback, and fake-provider snapshot tests without D-Bus work during assembly.

## 2. Bluetooth discovery and device control

- [x] 2.1 Implement command routing for a 15-second concurrent scan across all powered adapters, owned-discovery cleanup, merged address-deduplicated results, and next-scan result replacement.
- [x] 2.2 Implement serialized per-address connect, pair-then-trust-then-connect, and disconnect operations with observed-state reconciliation, progress, retryable errors, and cancellation on adapter/service loss.
- [x] 2.3 Register and release Alice's BlueZ default pairing agent; explicitly fail pairing when default-agent ownership is unavailable.
- [x] 2.4 Implement tokenized pairing/authorization prompt routing for PIN/passkey entry/display, numeric confirmation, device/service allow-deny requests, cancellation, and unsolicited-request rejection.

## 3. Bridge and Flutter state

- [x] 3.1 Expose Bluetooth snapshot types and scan/connect/disconnect/prompt-response APIs through FRB, regenerate Rust/Dart bindings, and add platform adapter methods.
- [x] 3.2 Add Bluetooth as a separately frozen and content-compared `AliceSnapshotState` slice with rebuild-isolation tests.
- [x] 3.3 Add `AlicePanel.bluetooth`, conditional panel lifecycle handling, panel sizing, host binding, and app-level action callbacks; close the panel when Bluetooth becomes unavailable.

## 4. Bluetooth user interface

- [x] 4.1 Add Alice icon descriptors for Bluetooth and supported device categories, including a generic fallback.
- [x] 4.2 Add the conditional icon-only Bluetooth top-bar module immediately before Network, including open-panel styling and module-order tests for both availability states.
- [x] 4.3 Build the standalone Bluetooth panel with exclusive Connected, Known devices, and Nearby lists; render aliases/names/address fallback, class icons, scan state, and retained scan results.
- [x] 4.4 Add Connect, Disconnect, per-device in-progress state, retryable inline error, and scan controls to the panel.
- [x] 4.5 Build modal pairing and authorization dialogs for PIN/passkey, display-only passkey, numeric confirmation, and explicit allow/deny, wiring all responses to the native prompt API.
- [x] 4.6 Add hermetic Flutter widget tests for conditional visibility, aggregation/list precedence, labels/icons, scan retention, actions/progress/errors, pairing dialogs, authorization, and panel closure.

## 5. Verification

- [x] 5.1 Run Rust formatting and native tests, including all Bluetooth fake transport/agent coverage.
- [x] 5.2 Run Flutter formatting, analysis, and test suites; verify no test requires BlueZ, D-Bus, Bluetooth hardware, or nearby devices.
- [x] 5.3 Validate the OpenSpec change strictly and resolve any proposal, spec, design, or task validation findings.
