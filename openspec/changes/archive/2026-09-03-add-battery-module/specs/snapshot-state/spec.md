## ADDED Requirements

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
