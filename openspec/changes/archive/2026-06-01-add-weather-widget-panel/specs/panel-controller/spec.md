## MODIFIED Requirements

### Requirement: Supported panel identities
Alice SHALL model the implemented panels as media, clock, weather, tray overflow, power, and notifications.

#### Scenario: Native panel command arrives
- **WHEN** Dart receives a native panel id string
- **THEN** Alice SHALL map known ids to the corresponding Flutter panel enum
- **AND** Alice SHALL ignore unknown ids by rendering no panel content

### Requirement: Panel sizing
Alice SHALL use implemented per-panel sizing rules.

#### Scenario: Size is requested
- **WHEN** Alice sizes a panel
- **THEN** media SHALL use 360x268, power SHALL use 280x292, clock SHALL use width 320 and half screen height, weather SHALL use width 320 with height constrained by screen height and a minimum placeholder height, tray overflow SHALL scale with overflow item count within bounds, and notifications SHALL scale with notification count within bounds

### Requirement: Granular panel open-state notifications
Alice SHALL expose granular listenable panel open states for media, clock, weather, tray overflow, notifications, and power in addition to preserving the existing single-open-panel controller semantics.

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
- **AND** Alice SHALL NOT rebuild clock, weather, tray overflow, notification, or power highlight consumers because of that panel state change

#### Scenario: Media panel switches to clock panel
- **WHEN** the open panel changes from media to clock
- **THEN** Alice SHALL rebuild the media highlight consumer and the clock highlight consumer
- **AND** Alice SHALL NOT rebuild weather, tray overflow, notification, or power highlight consumers because of that panel state change

## ADDED Requirements

### Requirement: Weather panel toggle integration
Alice SHALL allow the weather bar widget to toggle the weather panel using the same single-open-panel semantics as other panels.

#### Scenario: Weather widget opens panel
- **WHEN** the user activates the weather bar widget while no panel is open
- **THEN** Alice SHALL open the weather panel
- **AND** Alice SHALL store the widget anchor for native panel positioning

#### Scenario: Weather widget closes panel
- **WHEN** the user activates the weather bar widget while the weather panel is already open
- **THEN** Alice SHALL close the weather panel and clear its anchor

#### Scenario: Weather replaces another panel
- **WHEN** the user activates the weather bar widget while another panel is open
- **THEN** Alice SHALL replace the open panel with the weather panel
