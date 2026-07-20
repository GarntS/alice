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
Alice SHALL define omitted optional configuration values from the typed `AliceConfig` defaults rather than repeating scalar fallback literals in raw-to-typed conversion. The shipped default template and `AliceConfig::default()` SHALL produce equivalent effective typed configuration. The second built-in world-clock default SHALL follow the template's `Australia/Sydney` IANA time zone, including its current daylight-saving abbreviation and UTC offset.

#### Scenario: Missing optional sections
- **WHEN** the YAML omits optional `theme`, `network`, `tray`, `clock`, `power`, `calendar`, `notifications`, or `weather` fields
- **THEN** Alice SHALL use built-in typed defaults for omitted fields
- **AND** raw-to-typed conversion SHALL preserve implemented normalization and minimum-value rules

#### Scenario: Shipped template is parsed
- **WHEN** Alice parses `DEFAULT_CONFIG_TEMPLATE`
- **THEN** its effective typed configuration SHALL equal `AliceConfig::default()`
- **AND** this parity SHALL be verified by a deterministic automated contract test

#### Scenario: Sydney is in standard or daylight time
- **WHEN** `AliceConfig::default()` constructs its second world-clock entry
- **THEN** Alice SHALL resolve `Australia/Sydney` using `chrono-tz`
- **AND** the label and offset SHALL reflect the current AEST or AEDT period

#### Scenario: Invalid accent color or empty commands
- **WHEN** `theme.accent` is not a `#RRGGBB` hex color
- **THEN** Alice SHALL use the default accent color `#4C956C`
- **WHEN** a power command is empty or whitespace
- **THEN** Alice SHALL use that action's typed default command

### Requirement: Supported configuration model
Alice SHALL expose typed configuration for theme mode, accent color, transparent top bar preference, panel gap, network label visibility, tray visibility limit, local and additional time zones, power commands, optional Google Calendar credentials, notification settings, and weather settings.

#### Scenario: Typed config is loaded by Flutter
- **WHEN** Flutter calls `loadConfig`
- **THEN** Rust SHALL return the typed configuration over flutter_rust_bridge
- **AND** Flutter SHALL map theme modes, colors, transparent top bar preference, time zones, power commands, panel gap, calendar presence, notification settings, and weather settings into its UI configuration model

#### Scenario: Notification popup config is omitted
- **WHEN** the YAML omits `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL default `show_notification_popup` to `true`
- **AND** Alice SHALL default `notification_display_time_ms` to `5000`
- **AND** Alice SHALL default `expire_critical_notifications` to `false`

#### Scenario: Notification popup config is provided
- **WHEN** the YAML provides `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL expose those values in the typed configuration model returned to Flutter

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

### Requirement: Weather configuration parsing
Alice SHALL parse a top-level `weather` configuration section into typed Rust and Flutter configuration models.

#### Scenario: Weather config is omitted
- **WHEN** the YAML omits the `weather` section
- **THEN** Alice SHALL default weather to enabled
- **AND** Alice SHALL default `forecast_language` to `en`
- **AND** Alice SHALL default `forecast_units` to `us`
- **AND** Alice SHALL default `refresh_interval` to `3600`

#### Scenario: Weather config is provided
- **WHEN** the YAML provides `weather.enable`, `weather.pirate_weather_key`, `weather.forecast_lat`, `weather.forecast_long`, `weather.forecast_language`, `weather.forecast_units`, or `weather.refresh_interval`
- **THEN** Alice SHALL expose those values in the typed configuration model returned to Flutter

#### Scenario: Weather refresh interval is below minimum
- **WHEN** the YAML provides `weather.refresh_interval` below `300`
- **THEN** Alice SHALL expose `300` as the effective refresh interval

#### Scenario: Disabled weather config is incomplete
- **WHEN** `weather.enable` is `false`
- **THEN** Alice SHALL allow weather credential and coordinate fields to be absent or empty

### Requirement: Weather configuration validation
Alice SHALL validate required weather collection fields only when weather is enabled.

#### Scenario: Required weather credentials or coordinates are absent
- **WHEN** weather is enabled and `pirate_weather_key`, `forecast_lat`, or `forecast_long` is absent or empty
- **THEN** Alice SHALL print a Rust log error identifying the missing field
- **AND** Alice SHALL continue running

#### Scenario: Weather coordinates are out of range
- **WHEN** weather is enabled and `forecast_lat` is outside `-90..90` or `forecast_long` is outside `-180..180`
- **THEN** Alice SHALL print a Rust log error identifying the invalid field
- **AND** Alice SHALL continue running

#### Scenario: Weather API key appears in errors
- **WHEN** Alice logs weather configuration or request errors
- **THEN** Alice SHALL redact the Pirate Weather API key from the logged output

