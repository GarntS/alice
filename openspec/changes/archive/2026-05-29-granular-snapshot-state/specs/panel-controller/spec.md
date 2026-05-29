## ADDED Requirements

### Requirement: Granular panel open-state notifications
Alice SHALL expose granular listenable panel open states for media, clock, tray overflow, notifications, and power in addition to preserving the existing single-open-panel controller semantics.

#### Scenario: One panel opens from closed state
- **WHEN** the user opens a panel while no panel is open
- **THEN** Alice SHALL notify the open-state listener for that panel
- **AND** Alice SHALL NOT notify open-state listeners for other panels

#### Scenario: Open panel switches
- **WHEN** the user switches from one open panel to another panel
- **THEN** Alice SHALL notify the open-state listener for the previously open panel
- **AND** Alice SHALL notify the open-state listener for the newly open panel
- **AND** Alice SHALL NOT notify open-state listeners for panels whose open state did not change

#### Scenario: Same panel closes
- **WHEN** the user toggles the currently open panel closed
- **THEN** Alice SHALL notify the open-state listener for that panel
- **AND** Alice SHALL NOT notify open-state listeners for other panels

### Requirement: Panel highlight rebuild isolation
Alice SHALL bind bar module highlight UI to granular panel open-state listenables so panel toggles rebuild only modules whose highlighted state changes.

#### Scenario: Media panel opens
- **WHEN** the media panel opens from a closed state
- **THEN** Alice SHALL rebuild the media highlight consumer
- **AND** Alice SHALL NOT rebuild clock, tray overflow, notification, or power highlight consumers because of that panel state change

#### Scenario: Media panel switches to clock panel
- **WHEN** the open panel changes from media to clock
- **THEN** Alice SHALL rebuild the media highlight consumer and the clock highlight consumer
- **AND** Alice SHALL NOT rebuild tray overflow, notification, or power highlight consumers because of that panel state change
