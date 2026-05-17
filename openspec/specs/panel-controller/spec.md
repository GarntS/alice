# Panel Controller Specification

## Purpose
Define Flutter-side panel identity, toggle behavior, anchor tracking, sizing, and bridge coordination.

## Requirements

### Requirement: Supported panel identities
Alice SHALL model the implemented panels as media, clock, tray overflow, power, and notifications.

#### Scenario: Native panel command arrives
- **WHEN** Dart receives a native panel id string
- **THEN** Alice SHALL map known ids to the corresponding Flutter panel enum
- **AND** Alice SHALL ignore unknown ids by rendering no panel content

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
- **THEN** media SHALL use 360x268, power SHALL use 280x292, clock SHALL use width 320 and half screen height, tray overflow SHALL scale with overflow item count within bounds, and notifications SHALL scale with notification count within bounds
