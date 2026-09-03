## 1. Native configuration and battery provider

- [x] 1.1 Add typed Rust battery configuration (`enable`, optional `device_name`) with default-enabled parsing, blank-name normalization, and default-template documentation.
- [x] 1.2 Add tests covering omitted, explicit, disabled, and blank battery configuration plus default-template parity.
- [x] 1.3 Implement a testable sysfs battery provider that honors a configured device or deterministically discovers a `type=Battery` entry, and returns no state for absent, unreadable, invalid, or out-of-range data.
- [x] 1.4 Add provider tests using temporary power-supply fixtures for selection precedence, auto-discovery, missing devices, malformed capacity, and status reads.

## 2. Snapshot contract and bridge

- [x] 2.1 Add optional battery capacity/status state to the Rust `BarSnapshot` contract and snapshot provider aggregation boundary.
- [x] 2.2 Wire the enabled battery provider into the one-second runtime snapshot path with no-state failure fallback.
- [x] 2.3 Regenerate flutter_rust_bridge bindings and extend Rust snapshot aggregation tests for successful and failed battery provider results.
- [x] 2.4 Expose battery configuration through `AliceUiConfig`, map it into Flutter `AliceConfig`, and update fallback/test configuration helpers.

## 3. Flutter state and bar presentation

- [x] 3.1 Add an independently diffed and listenable optional battery slice to `AliceSnapshotState`, including snapshot reconstruction and disposal coverage.
- [x] 3.2 Add semantic regular and duotone `AliceIcons` descriptors for full, high, medium, low, warning, and charging horizontal battery icons.
- [x] 3.3 Create the battery bar metric module with `<capacity>%` text, charging/full override, and the agreed capacity-to-icon bands.
- [x] 3.4 Bind the enabled battery module into the right-side top bar through its granular battery listenable and omit it when state is absent.

## 4. Verification and documentation

- [x] 4.1 Add Flutter unit/widget tests for icon selection boundaries, charging/full override, absence behavior, icon style, and percentage formatting.
- [x] 4.2 Extend snapshot-state and top-bar rebuild-isolation tests to prove battery-only updates rebuild only battery consumers.
- [x] 4.3 Document battery configuration and auto-detection behavior in the README.
- [x] 4.4 Run Rust and Flutter formatting, analysis, and relevant test suites; fix all regressions.
