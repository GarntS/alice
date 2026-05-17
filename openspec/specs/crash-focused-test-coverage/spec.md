# crash-focused-test-coverage Specification

## Purpose
TBD - created by archiving change add-crash-focused-tests. Update Purpose after archive.
## Requirements
### Requirement: Flutter crash-focused widget coverage
Alice SHALL include Flutter tests that render representative bar and panel UI states from synthetic snapshots and configuration without requiring live native services.

#### Scenario: Top bar renders a mixed snapshot
- **WHEN** the Flutter test suite pumps the top bar with workspaces, media, system metrics, network state, tray overflow, unread notifications, and power controls
- **THEN** the widget tree SHALL build without uncaught Flutter exceptions
- **AND** the rendered bar SHALL expose the expected snapshot-driven labels and controls

#### Scenario: Panels render edge-case snapshots
- **WHEN** the Flutter test suite pumps media, tray overflow, notifications, power, and calendar-facing panel widgets with empty and populated edge-case data
- **THEN** each panel SHALL build within bounded constraints without uncaught Flutter exceptions
- **AND** empty states, long text, invalid image bytes, and action callbacks SHALL be handled without crashing

### Requirement: Panel coordination coverage
Alice SHALL include tests for Flutter panel state transitions and native method-channel payload construction.

#### Scenario: Panel controller transitions are exercised
- **WHEN** tests toggle the same panel, toggle a different panel, and close an already-closed controller
- **THEN** the controller SHALL maintain at most one open panel
- **AND** it SHALL clear or replace anchors according to the implemented toggle semantics

#### Scenario: Platform show and hide payloads are exercised
- **WHEN** tests call the platform adapter's panel show and hide methods using a mocked method channel
- **THEN** the adapter SHALL send `showPanel` and `hidePanel` method calls with the implemented panel id, anchor, alignment, size, tray-icon inclusion, and panel-gap payload fields

### Requirement: Rust crash-focused native coverage
Alice SHALL include Rust tests for native boundaries that can fail during normal desktop use without relying on live desktop services.

#### Scenario: Native configuration tests are hermetic
- **WHEN** Rust tests exercise config creation and parsing
- **THEN** they SHALL use explicit temporary paths or in-memory YAML
- **AND** they SHALL NOT assert against the developer's real `$XDG_CONFIG_HOME` or `$HOME/.config/alice/config.yaml`

#### Scenario: Snapshot provider failures are exercised
- **WHEN** Rust tests assemble a snapshot from fake providers where individual providers fail
- **THEN** snapshot construction SHALL complete without panic
- **AND** it SHALL use the implemented empty, null, zero, disconnected, or placeholder fallback values for failed providers

### Requirement: Test suite commands
Alice SHALL provide stable local test commands for the crash-focused suite.

#### Scenario: Flutter tests run locally
- **WHEN** `flutter test` is run from the repository root
- **THEN** it SHALL discover and run the Flutter test suite
- **AND** it SHALL complete without requiring Wayland, GTK layer-shell, D-Bus, Google Calendar, or network access

#### Scenario: Rust tests run locally
- **WHEN** `cargo test --manifest-path native/Cargo.toml` is run from the repository root
- **THEN** it SHALL complete without depending on the developer's real desktop session or user configuration

