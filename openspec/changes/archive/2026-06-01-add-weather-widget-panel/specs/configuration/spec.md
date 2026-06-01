## MODIFIED Requirements

### Requirement: Defaults and invalid-value fallback
Alice SHALL provide safe defaults for missing optional configuration fields and SHALL fall back for invalid or unusable values where implemented.

#### Scenario: Missing optional sections
- **WHEN** the YAML omits optional `theme`, `network`, `tray`, `clock`, `power`, `calendar`, `notifications`, or `weather` fields
- **THEN** Alice SHALL use built-in defaults for omitted fields

#### Scenario: Invalid accent color or empty commands
- **WHEN** `theme.accent` is not a `#RRGGBB` hex color
- **THEN** Alice SHALL use the default accent color `#4C956C`
- **WHEN** a power command is empty or whitespace
- **THEN** Alice SHALL use that action's default command

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

## ADDED Requirements

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
