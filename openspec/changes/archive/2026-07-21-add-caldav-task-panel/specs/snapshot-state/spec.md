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
- **THEN** Alice SHALL publish initial values for workspaces, media, memory usage, CPU usage, network, clock, weather, tray items, notifications, normalized CalDAV tasks, and CalDAV synchronization state

## ADDED Requirements

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
