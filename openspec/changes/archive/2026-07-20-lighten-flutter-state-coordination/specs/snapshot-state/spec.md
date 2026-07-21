## MODIFIED Requirements

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

## ADDED Requirements

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
