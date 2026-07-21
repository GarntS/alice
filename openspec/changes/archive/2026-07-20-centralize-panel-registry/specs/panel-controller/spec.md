## MODIFIED Requirements

### Requirement: Supported panel identities
Alice SHALL model the implemented panels as media, clock, weather, tray overflow, power, and notifications. Each modeled panel SHALL have one canonical native wire id used consistently for parsing and panel-show requests.

#### Scenario: Native panel command arrives
- **WHEN** Dart receives a native panel id string
- **THEN** Alice SHALL map `media`, `clock`, `weather`, `trayOverflow`, `power`, and `notifications` to their corresponding Flutter panel enum values
- **AND** Alice SHALL ignore unknown or null ids by rendering no panel content

#### Scenario: Flutter requests a native panel
- **WHEN** Flutter opens a modeled panel
- **THEN** Alice SHALL send that panel's canonical wire id in the native `showPanel` request
- **AND** parsing the emitted id SHALL return the original panel enum value

### Requirement: Granular panel open-state notifications
Alice SHALL expose granular listenable panel open states for every modeled panel in addition to preserving the existing single-open-panel controller semantics. The named media, clock, weather, tray overflow, notifications, and power listenable accessors SHALL remain available.

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

#### Scenario: Granular state is requested for every modeled panel
- **WHEN** a caller requests the open-state listenable for any value in the modeled panel enum
- **THEN** Alice SHALL return that panel's stable listenable
- **AND** the listenable SHALL initially be false for a new controller
