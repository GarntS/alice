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
Alice SHALL build Material 3 color schemes from the configured accent color for both light and dark themes.

#### Scenario: Theme is built
- **WHEN** Alice builds a light or dark theme
- **THEN** Alice SHALL use `ColorScheme.fromSeed` with the configured accent color
- **AND** Alice SHALL apply Alice-specific surface, foreground, secondary, and transparent scaffold colors

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

