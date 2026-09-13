## MODIFIED Requirements

### Requirement: Snapshot state ingestion
Alice SHALL maintain a Flutter-side `AliceSnapshotState` that represents the current UI state derived from the latest `BarSnapshot`.

#### Scenario: Snapshot arrives from Rust
- **WHEN** Flutter receives a `BarSnapshot` from `watchBarSnapshots`
- **THEN** Alice SHALL ingest it into `AliceSnapshotState`
- **AND** Alice SHALL NOT call root application `setState` solely because the snapshot arrived
- **AND** Alice SHALL preserve the latest values for all snapshot fields needed by bar, panel, and popup UI

#### Scenario: Initial snapshot is ingested
- **WHEN** the first `BarSnapshot` is ingested
- **THEN** Alice SHALL publish initial values for workspaces, media, memory usage, CPU usage, Bluetooth, network, clock, weather, tray items, notifications, normalized CalDAV tasks, and CalDAV synchronization state

## ADDED Requirements

### Requirement: Granular Bluetooth snapshot state
`AliceSnapshotState` SHALL expose Bluetooth as an independently listenable, deeply immutable snapshot slice and SHALL notify it only when Bluetooth availability, device observations, scanning state, operation state, prompt state, or error state changes.

#### Scenario: Bluetooth only changes
- **WHEN** a new snapshot differs only by Bluetooth state
- **THEN** Alice SHALL notify the Bluetooth slice
- **AND** Alice SHALL NOT notify workspace, media, metric, network, clock, weather, tray, notification, or task slices solely because of that change

#### Scenario: Equivalent Bluetooth data arrives
- **WHEN** a new snapshot contains fresh Bluetooth collection instances with equivalent content to the current Bluetooth state
- **THEN** Alice SHALL treat the Bluetooth slice as unchanged
- **AND** Alice SHALL NOT notify Bluetooth listeners
