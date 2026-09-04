# Theme System Specification

## Purpose
Define Alice's implemented Material theme behavior, accent color usage, and shared widget visual states.
## Requirements
### Requirement: Theme mode selection
Alice SHALL support Flutter `system`, `light`, and `dark` theme modes based on configuration.

#### Scenario: Config theme mode is loaded
- **WHEN** the configured theme mode is mapped into Flutter
- **THEN** Alice SHALL set `MaterialApp.themeMode` to system, light, or dark accordingly

### Requirement: Accent-derived Material theme
Alice SHALL build explicit light and dark Material color schemes from Alice-owned color tokens instead of a Material 3 seeded palette. Each scheme SHALL retain Flutter Material theme compatibility while mapping the configured exact accent to `primary`, the subtle accent token to `primaryContainer`, and the neutral raised-container token to `secondaryContainer`.

#### Scenario: Theme is built
- **WHEN** Alice builds a light or dark theme
- **THEN** it SHALL NOT derive the color scheme with `ColorScheme.fromSeed`
- **AND** it SHALL use Alice-defined neutral surface, foreground, and secondary colors
- **AND** it SHALL expose an explicit Material color scheme and transparent scaffold colors

#### Scenario: Material component consumes theme roles
- **WHEN** an Alice or stock Material component reads a mapped primary, container, surface, outline, error, or warning theme role
- **THEN** it SHALL receive the corresponding explicit Alice color token

### Requirement: Highlighted panel targets
Bar controls associated with open panels SHALL expose a highlighted visual state.

#### Scenario: Panel is open
- **WHEN** a panel-associated bar module corresponds to the currently open panel
- **THEN** Alice SHALL render that module using its highlighted styling

### Requirement: Alert and warning colors
Metric widgets SHALL use warning and alert colors when their implemented thresholds are met.

#### Scenario: Memory crosses thresholds
- **WHEN** memory usage is at least 75 percent
- **THEN** the memory pill SHALL use the warning color
- **WHEN** memory usage is at least 90 percent
- **THEN** the memory pill SHALL use the alert color

#### Scenario: CPU crosses thresholds
- **WHEN** CPU usage is at least 2.4 aggregate cores
- **THEN** the CPU pill SHALL use the warning color
- **WHEN** CPU usage is at least 3.2 aggregate cores
- **THEN** the CPU pill SHALL use the alert color

### Requirement: Non-accent duotone secondary colors
Alice SHALL define fixed gray colors for the secondary layer of duotone icons when accent-colored icon layers are disabled.

#### Scenario: Light theme uses a gray secondary layer
- **WHEN** Alice renders a duotone icon in the light theme with `theme.use_accent_on_icons` set to `false`
- **THEN** the icon's secondary layer SHALL use Alice's fixed dark gray token

#### Scenario: Dark theme uses a gray secondary layer
- **WHEN** Alice renders a duotone icon in the dark theme with `theme.use_accent_on_icons` set to `false`
- **THEN** the icon's secondary layer SHALL use Alice's fixed light gray token

