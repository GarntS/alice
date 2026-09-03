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
- **THEN** Alice SHALL publish initial values for workspaces, media, memory usage, CPU usage, network, clock, weather, tray items, notifications, normalized CalDAV tasks, and CalDAV synchronization state

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

### Requirement: Granular CalDAV task state
`AliceSnapshotState` SHALL expose independently listenable normalized task and CalDAV synchronization-state slices and SHALL compare their complete displayed content rather than list identity.

#### Scenario: Equivalent task snapshot is received
- **WHEN** a new snapshot contains a fresh task-list instance with the same task identities, titles, dates, completion state, priorities, and collection metadata
- **THEN** Alice SHALL treat the task slice as unchanged
- **AND** Alice SHALL NOT notify task-list consumers

#### Scenario: Task content changes
- **WHEN** a task's displayed or ordering-relevant content changes
- **THEN** Alice SHALL notify the task-list slice
- **AND** Alice SHALL NOT notify unrelated media, metric, network, weather, tray, or notification slices solely because of the task change

#### Scenario: Synchronization state changes without task content changing
- **WHEN** CalDAV freshness, loading, last-success, or error state changes while normalized tasks remain equivalent
- **THEN** Alice SHALL notify synchronization-state consumers
- **AND** Alice SHALL NOT notify raw task-list consumers

### Requirement: Derived task due projections
`AliceSnapshotState` SHALL publish independently listenable counts for active tasks due today and active overdue tasks, derived from normalized task data and the machine-local current date.

#### Scenario: Task changes due count
- **WHEN** task data changes in a way that changes the due-today or overdue count
- **THEN** Alice SHALL notify only each changed count projection and task-list consumers whose raw content changed

#### Scenario: Task content changes without counts changing
- **WHEN** task title, collection label, or other content changes while due-today and overdue counts remain equal
- **THEN** Alice SHALL notify the raw task-list slice
- **AND** Alice SHALL NOT notify unchanged count projections

#### Scenario: Local date changes
- **WHEN** the machine-local current date advances while task records remain unchanged
- **THEN** Alice SHALL recompute due-today and overdue counts
- **AND** Alice SHALL notify each projection whose value changed

#### Scenario: Completed or undated task is counted
- **WHEN** Alice derives due-today and overdue counts
- **THEN** Alice SHALL exclude completed, cancelled, and undated tasks from both counts

### Requirement: Task rebuild isolation
Alice SHALL bind task bar and panel consumers to granular task state so CalDAV updates and unrelated snapshot updates rebuild only their consumers.

#### Scenario: Due count changes
- **WHEN** a snapshot update changes only task data and changes a due count
- **THEN** Alice SHALL rebuild the task bar count consumer and any mounted task-list consumer
- **AND** Alice SHALL NOT rebuild unrelated workspace, media, metric, network, clock, weather, tray, notification, or power modules because of that update

#### Scenario: Synchronization status changes only
- **WHEN** a snapshot update changes only CalDAV synchronization state
- **THEN** Alice SHALL rebuild task synchronization-state consumers
- **AND** Alice SHALL NOT rebuild the raw task-list consumer or unrelated modules

#### Scenario: CPU changes while task panel is open
- **WHEN** a snapshot update changes only CPU usage while the task panel is mounted
- **THEN** Alice SHALL rebuild the CPU consumer
- **AND** Alice SHALL NOT rebuild the task bar module or task panel because of that CPU update

### Requirement: Granular battery snapshot state
`AliceSnapshotState` SHALL retain optional battery state and expose it as an independently listenable slice. It SHALL notify battery consumers only when the battery state changes.

#### Scenario: Battery state changes
- **WHEN** a new snapshot changes only battery capacity, status, or availability
- **THEN** Alice SHALL notify the battery state slice
- **AND** Alice SHALL NOT notify unrelated workspace, media, memory, CPU, network, clock, weather, tray, notification, or task slices

#### Scenario: Unchanged battery state is received
- **WHEN** a new snapshot contains battery state equal to the current battery state
- **THEN** Alice SHALL not notify battery consumers

### Requirement: Battery rebuild isolation
Alice SHALL bind the top-bar battery module to the granular battery listenable.

#### Scenario: Battery-only update arrives
- **WHEN** a snapshot update changes only battery state
- **THEN** Alice SHALL rebuild the battery module or its local builder
- **AND** Alice SHALL NOT rebuild unrelated top-bar modules solely because of that update

