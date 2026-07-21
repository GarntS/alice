# Panel Controller Specification

## Purpose
Define Flutter-side panel identity, toggle behavior, anchor tracking, sizing, and bridge coordination.
## Requirements
### Requirement: Supported panel identities
Alice SHALL model the implemented panels as media, clock, tasks, weather, tray overflow, power, and notifications. Each modeled panel SHALL have one canonical native wire id used consistently for parsing and panel-show requests.

#### Scenario: Native panel command arrives
- **WHEN** Dart receives a native panel id string
- **THEN** Alice SHALL map `media`, `clock`, `tasks`, `weather`, `trayOverflow`, `power`, and `notifications` to their corresponding Flutter panel enum values
- **AND** Alice SHALL ignore unknown or null ids by rendering no panel content

#### Scenario: Flutter requests a native panel
- **WHEN** Flutter opens a modeled panel
- **THEN** Alice SHALL send that panel's canonical wire id in the native `showPanel` request
- **AND** parsing the emitted id SHALL return the original panel enum value

### Requirement: Toggle semantics
Alice SHALL track at most one open panel in the Flutter panel controller.

#### Scenario: Same panel is toggled
- **WHEN** the user toggles the panel that is already open
- **THEN** Alice SHALL close the panel and clear its anchor

#### Scenario: Different panel is toggled
- **WHEN** the user toggles a different panel
- **THEN** Alice SHALL replace the open panel and store the new anchor

### Requirement: Panel show/hide synchronization
Alice SHALL synchronize Flutter panel state with native `showPanel` and `hidePanel` method-channel calls.

#### Scenario: Open panel changes
- **WHEN** the panel controller reports an open panel with an anchor
- **THEN** Alice SHALL compute the panel size
- **AND** Alice SHALL send `showPanel` with panel id, anchor coordinates, alignment, size, tray icon inclusion flag, and panel top gap

#### Scenario: Panel closes
- **WHEN** no panel is open
- **THEN** Alice SHALL send `hidePanel` to the native runner

### Requirement: Panel sizing
Alice SHALL use implemented per-panel sizing rules.

#### Scenario: Size is requested
- **WHEN** Alice sizes a panel
- **THEN** media SHALL use 360x268, power SHALL use 280x292, clock SHALL use width 320 and half screen height, tasks SHALL use width 380 and size naturally up to a scrollable maximum height of 800, weather SHALL use width 320 with height constrained by screen height and a minimum placeholder height, tray overflow SHALL scale with overflow item count within bounds, and notifications SHALL scale with notification count within bounds

#### Scenario: Panel card is inset from its window
- **WHEN** Alice renders any panel card
- **THEN** its top inset SHALL be slightly smaller than its side and bottom insets
- **AND** shared and custom panel headings SHALL inherit the same reduction in window-top spacing

### Requirement: Granular panel open-state notifications
Alice SHALL expose granular listenable panel open states for every modeled panel in addition to preserving the existing single-open-panel controller semantics. The named media, clock, tasks, weather, tray overflow, notifications, and power listenable accessors SHALL remain available.

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

### Requirement: Panel highlight rebuild isolation
Alice SHALL bind bar module highlight UI to granular panel open-state listenables so panel toggles rebuild only modules whose highlighted state changes.

#### Scenario: Media panel opens
- **WHEN** the media panel opens from a closed state
- **THEN** Alice SHALL rebuild the media highlight consumer
- **AND** Alice SHALL NOT rebuild clock, tasks, weather, tray overflow, notification, or power highlight consumers because of that panel state change

#### Scenario: Media panel switches to clock panel
- **WHEN** the open panel changes from media to clock
- **THEN** Alice SHALL rebuild the media highlight consumer and the clock highlight consumer
- **AND** Alice SHALL NOT rebuild tasks, weather, tray overflow, notification, or power highlight consumers because of that panel state change

#### Scenario: Task panel opens
- **WHEN** the task panel opens from a closed state
- **THEN** Alice SHALL rebuild the task highlight consumer
- **AND** Alice SHALL NOT rebuild media, clock, weather, tray overflow, notification, or power highlight consumers because of that panel state change

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

### Requirement: Task panel toggle integration
Alice SHALL allow the task bar module to toggle the task panel using the same single-open-panel and anchor semantics as other panels.

#### Scenario: Task module opens panel
- **WHEN** the user activates the task module while no panel is open
- **THEN** Alice SHALL open the task panel
- **AND** Alice SHALL store the module's right-aligned anchor for native panel positioning

#### Scenario: Task module closes panel
- **WHEN** the user activates the task module while the task panel is already open
- **THEN** Alice SHALL close the task panel and clear its anchor

#### Scenario: Task module replaces another panel
- **WHEN** the user activates the task module while another panel is open
- **THEN** Alice SHALL replace the open panel with the task panel

