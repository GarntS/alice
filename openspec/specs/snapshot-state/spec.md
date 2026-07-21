# Snapshot State Specification

## Purpose
Define Flutter snapshot ingestion, granular state notifications, derived projections, and rebuild isolation.
## Requirements
### Requirement: Snapshot state ingestion
Alice SHALL maintain a Flutter-side `AliceSnapshotState` that represents the current UI state derived from the latest `BarSnapshot`.

#### Scenario: Snapshot arrives from Rust
- **WHEN** Flutter receives a `BarSnapshot` from `watchBarSnapshots`
- **THEN** Alice SHALL ingest it into `AliceSnapshotState`
- **AND** Alice SHALL NOT call root application `setState` solely because the snapshot arrived
- **AND** Alice SHALL preserve the latest values for all snapshot fields needed by bar, panel, and popup UI

#### Scenario: Initial snapshot is ingested
- **WHEN** the first `BarSnapshot` is ingested
- **THEN** Alice SHALL publish initial values for workspaces, media, memory usage, CPU usage, network, clock, tray items, and notifications

### Requirement: Granular raw slice notifications
`AliceSnapshotState` SHALL expose independently listenable raw snapshot slices and notify each slice only when that slice's value changes.

#### Scenario: CPU only changes
- **WHEN** a new snapshot differs only by CPU usage
- **THEN** Alice SHALL notify the CPU usage slice
- **AND** Alice SHALL NOT notify memory, media, workspace, network, clock, tray, or notification slices

#### Scenario: Clock only changes
- **WHEN** a new snapshot differs only by clock data
- **THEN** Alice SHALL notify the clock slice
- **AND** Alice SHALL NOT notify CPU, memory, media, workspace, network, tray, or notification slices

#### Scenario: Media only changes
- **WHEN** a new snapshot differs only by media data
- **THEN** Alice SHALL notify the media slice
- **AND** Alice SHALL NOT notify CPU, memory, workspace, network, clock, tray, or notification slices

### Requirement: Explicit snapshot diffing
Alice SHALL compare incoming snapshot fields using content-aware comparators rather than relying on Dart collection identity. Comparators SHALL include every snapshot field observed by a Flutter consumer and MAY delegate scalar-only generated models to their generated structural equality.

#### Scenario: Equivalent lists are received as new objects
- **WHEN** a new snapshot contains fresh list instances with the same workspace, tray, notification, or weather forecast contents as the current snapshot
- **THEN** Alice SHALL treat those slices as unchanged
- **AND** Alice SHALL NOT notify listeners for those slices

#### Scenario: List element content changes
- **WHEN** a new snapshot contains a workspace, tray item, notification, or weather forecast element whose relevant content differs from the current snapshot
- **THEN** Alice SHALL notify the corresponding list or weather slice

#### Scenario: Binary image data is unchanged
- **WHEN** tray icon bytes or notification image bytes represent unchanged image data
- **THEN** Alice SHALL avoid causing unrelated slice notifications because of new byte-list object identity

#### Scenario: Weather offset changes
- **WHEN** a weather snapshot differs from the current weather snapshot only in `offset`
- **THEN** Alice SHALL notify the weather slice
- **AND** weather consumers SHALL receive the new offset for forecast date and time calculations

### Requirement: Derived snapshot state
`AliceSnapshotState` SHALL publish derived listenable state for UI projections that are narrower than the full snapshot.

#### Scenario: Unread notification count changes
- **WHEN** notification data changes in a way that changes the unread notification count
- **THEN** Alice SHALL notify the unread notification count state
- **AND** widgets that only consume the unread count SHALL NOT depend on the full notifications list

#### Scenario: Notification content changes without unread count changing
- **WHEN** notification data changes but the unread notification count remains the same
- **THEN** Alice SHALL notify the notifications list state
- **AND** Alice SHALL NOT notify the unread notification count state

#### Scenario: Tray overflow projection changes
- **WHEN** tray items or the configured visible tray limit change in a way that changes visible tray items or overflow count
- **THEN** Alice SHALL notify only the affected tray projection states

### Requirement: Snapshot-driven rebuild isolation
Alice SHALL bind snapshot-driven widgets to granular snapshot-state listenables so only widgets consuming changed data are marked dirty and rebuilt for snapshot updates.

#### Scenario: CPU update rebuilds only CPU consumers
- **WHEN** a snapshot update changes only CPU usage
- **THEN** Alice SHALL rebuild the top-bar CPU module or its local builder
- **AND** Alice SHALL NOT rebuild top-bar media, workspace, memory, network, clock, tray, notification, or power modules because of that snapshot update
- **AND** Alice SHALL NOT rebuild active panel or popup widgets unless they consume the changed CPU state

#### Scenario: Notification unread badge update rebuilds only notification consumers
- **WHEN** a snapshot update changes only the unread notification count
- **THEN** Alice SHALL rebuild the notification badge module or its local builder
- **AND** Alice SHALL NOT rebuild unrelated bar modules because of that snapshot update

#### Scenario: Active media panel receives media update
- **WHEN** the media panel is open and a snapshot update changes only media data
- **THEN** Alice SHALL rebuild media consumers in the bar and media panel
- **AND** Alice SHALL NOT rebuild unrelated bar modules or unrelated panel content because of that snapshot update

### Requirement: Single-owner snapshot configuration propagation
Alice SHALL apply production configuration changes to `AliceSnapshotState` explicitly from the application state owner rather than through consumer widget lifecycle callbacks.

#### Scenario: Application loads changed configuration
- **WHEN** `AliceApp` successfully loads a configuration whose tray or notification settings affect derived snapshot state
- **THEN** `AliceApp` SHALL update `AliceSnapshotState` with that configuration
- **AND** affected derived snapshot state SHALL be recomputed
- **AND** `TopBar` and `AlicePanelCard` SHALL NOT mutate snapshot configuration during widget lifecycle updates

#### Scenario: Consumer widget rebuilds with unchanged state configuration
- **WHEN** `TopBar` or `AlicePanelCard` rebuilds
- **THEN** the rebuild SHALL NOT invoke snapshot configuration propagation as a side effect
- **AND** existing granular listenable bindings and rebuild isolation SHALL remain intact

