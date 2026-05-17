## MODIFIED Requirements

### Requirement: Supported configuration model
Alice SHALL expose typed configuration for theme mode, accent color, transparent top bar preference, panel gap, network label visibility, tray visibility limit, local and additional time zones, power commands, optional Google Calendar credentials, and notification settings.

#### Scenario: Typed config is loaded by Flutter
- **WHEN** Flutter calls `loadConfig`
- **THEN** Rust SHALL return the typed configuration over flutter_rust_bridge
- **AND** Flutter SHALL map theme modes, colors, transparent top bar preference, time zones, power commands, panel gap, and calendar presence into its UI configuration model

## ADDED Requirements

### Requirement: Transparent top bar configuration
Alice SHALL support an optional `theme.transparent_top_bar` boolean configuration field that controls only the outer top bar shell background and border.

#### Scenario: Transparent top bar omitted
- **WHEN** the YAML omits `theme.transparent_top_bar`
- **THEN** Alice SHALL default the transparent top bar preference to `false`

#### Scenario: Transparent top bar enabled
- **WHEN** `theme.transparent_top_bar` is set to `true`
- **THEN** Alice SHALL expose the transparent top bar preference as `true` in the typed configuration model

#### Scenario: Transparent top bar disabled
- **WHEN** `theme.transparent_top_bar` is set to `false`
- **THEN** Alice SHALL expose the transparent top bar preference as `false` in the typed configuration model
