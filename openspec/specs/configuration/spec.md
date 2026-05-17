# Configuration Specification

## Purpose
Define Alice's user configuration file, default generation behavior, and typed configuration contract shared between Rust and Flutter.
## Requirements
### Requirement: Config file discovery and first-run creation
Alice SHALL load configuration from `$XDG_CONFIG_HOME/alice/config.yaml`, falling back to `$HOME/.config/alice/config.yaml` when `XDG_CONFIG_HOME` is unset.

#### Scenario: Missing config file
- **WHEN** Alice loads configuration and the config file does not exist
- **THEN** Alice SHALL create parent directories as needed
- **AND** Alice SHALL write the shipped commented default configuration template
- **AND** Alice SHALL parse the resulting file into the typed configuration model

#### Scenario: Existing config file
- **WHEN** Alice loads configuration and the config file already exists
- **THEN** Alice SHALL leave the existing file in place
- **AND** Alice SHALL parse its contents as YAML

### Requirement: Defaults and invalid-value fallback
Alice SHALL provide safe defaults for missing optional configuration fields and SHALL fall back for invalid or unusable values where implemented.

#### Scenario: Missing optional sections
- **WHEN** the YAML omits optional `theme`, `network`, `tray`, `clock`, `power`, `calendar`, or `notifications` fields
- **THEN** Alice SHALL use built-in defaults for omitted fields

#### Scenario: Invalid accent color or empty commands
- **WHEN** `theme.accent` is not a `#RRGGBB` hex color
- **THEN** Alice SHALL use the default accent color `#4C956C`
- **WHEN** a power command is empty or whitespace
- **THEN** Alice SHALL use that action's default command

### Requirement: Supported configuration model
Alice SHALL expose typed configuration for theme mode, accent color, panel gap, network label visibility, tray visibility limit, local and additional time zones, power commands, optional Google Calendar credentials, and notification settings.

#### Scenario: Typed config is loaded by Flutter
- **WHEN** Flutter calls `loadConfig`
- **THEN** Rust SHALL return the typed configuration over flutter_rust_bridge
- **AND** Flutter SHALL map theme modes, colors, time zones, power commands, panel gap, and calendar presence into its UI configuration model

### Requirement: Time zone entry resolution
Alice SHALL resolve configured additional clock time zones from exactly the implemented inputs: fixed offset hours, IANA time zone names, or known abbreviations.

#### Scenario: Time zone name is configured
- **WHEN** an additional time zone uses `tz_name`
- **THEN** Alice SHALL resolve the current UTC offset and abbreviation using `chrono-tz`
- **AND** Alice SHALL use an explicit `label` override when provided

#### Scenario: Abbreviation or offset is configured
- **WHEN** an additional time zone uses a known `tz_abbrev_name`
- **THEN** Alice SHALL map it to the implemented fixed offset table
- **WHEN** an entry uses `offset_hours`
- **THEN** Alice SHALL use that fixed offset and derive a UTC-style label unless a label is provided

### Requirement: Hermetic configuration testability
Alice SHALL support configuration tests that exercise default creation, existing-file parsing, and fallback behavior through explicit test-controlled paths or in-memory YAML.

#### Scenario: Tests load from an explicit path
- **WHEN** tests need to verify config file creation or parsing
- **THEN** they SHALL use a temporary explicit config path
- **AND** they SHALL NOT read or assert against the developer's real Alice config file

#### Scenario: Tests parse YAML in memory
- **WHEN** tests need to verify defaults, invalid-value fallback, optional sections, or typed configuration mapping
- **THEN** they SHALL parse controlled YAML input in memory where possible
- **AND** they SHALL NOT require environment variables to point at a particular real config directory

