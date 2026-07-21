## MODIFIED Requirements

### Requirement: Defaults and invalid-value fallback
Alice SHALL define omitted optional configuration values from the typed `AliceConfig` defaults rather than repeating scalar fallback literals in raw-to-typed conversion. The shipped default template and `AliceConfig::default()` SHALL produce equivalent effective typed configuration. The second built-in world-clock default SHALL follow the template's `Australia/Sydney` IANA time zone, including its current daylight-saving abbreviation and UTC offset.

#### Scenario: Missing optional sections
- **WHEN** the YAML omits optional `theme`, `network`, `tray`, `clock`, `power`, `calendar`, `caldav`, `notifications`, or `weather` fields
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
Alice SHALL expose typed configuration for theme mode, accent color, transparent top bar preference, panel gap, network label visibility, tray visibility limit, local and additional time zones, power commands, optional Google Calendar credentials, optional CalDAV account settings, notification settings, and weather settings.

#### Scenario: Typed config is loaded by Flutter
- **WHEN** Flutter calls `loadConfig`
- **THEN** Rust SHALL return the typed configuration over flutter_rust_bridge
- **AND** Flutter SHALL map theme modes, colors, transparent top bar preference, time zones, power commands, panel gap, Google Calendar presence, CalDAV presence and settings, notification settings, and weather settings into its UI configuration model

#### Scenario: Notification popup config is omitted
- **WHEN** the YAML omits `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL default `show_notification_popup` to `true`
- **AND** Alice SHALL default `notification_display_time_ms` to `5000`
- **AND** Alice SHALL default `expire_critical_notifications` to `false`

#### Scenario: Notification popup config is provided
- **WHEN** the YAML provides `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL expose those values in the typed configuration model returned to Flutter

## ADDED Requirements

### Requirement: CalDAV configuration parsing
Alice SHALL parse an optional top-level `caldav` section containing a principal URL, an `allow_http` transport opt-in, username, inline token, collection-href allowlist, polling interval, and optional custom CA certificate path.

#### Scenario: CalDAV config is omitted
- **WHEN** the YAML omits the `caldav` section
- **THEN** Alice SHALL expose no CalDAV configuration
- **AND** Alice SHALL leave the CalDAV runtime and task UI disabled

#### Scenario: CalDAV config is provided
- **WHEN** the YAML provides non-empty `caldav.principal_url`, `caldav.username`, `caldav.token`, and `caldav.collection_hrefs`
- **THEN** Alice SHALL expose those values through the typed Rust configuration
- **AND** Alice SHALL expose CalDAV presence and non-secret UI settings through Flutter configuration mapping

#### Scenario: HTTP opt-in is omitted
- **WHEN** the YAML omits `caldav.allow_http`
- **THEN** Alice SHALL default it to `false`
- **AND** Alice SHALL reject an `http://` principal URL

#### Scenario: HTTP opt-in is enabled
- **WHEN** the YAML sets `caldav.allow_http` to `true` and provides an `http://` principal URL
- **THEN** Alice SHALL permit HTTP requests only to that principal's exact origin
- **AND** Alice SHALL preserve credential redaction and cross-origin request rejection

#### Scenario: Polling interval is omitted
- **WHEN** the YAML omits `caldav.poll_interval_secs`
- **THEN** Alice SHALL use an effective polling interval of 60 seconds

#### Scenario: Polling interval is below minimum
- **WHEN** the YAML provides `caldav.poll_interval_secs` below 1
- **THEN** Alice SHALL use an effective polling interval of 1 second

#### Scenario: Custom CA path is provided
- **WHEN** the YAML provides a non-empty `caldav.ca_certificate_path`
- **THEN** Alice SHALL expose the normalized path to the native CalDAV client

### Requirement: CalDAV configuration validation and redaction
Alice SHALL validate required CalDAV fields before starting synchronization and SHALL keep the inline token out of logs and Flutter UI state.

#### Scenario: Required CalDAV value is absent
- **WHEN** the `caldav` section is present but the principal URL, username, token, or collection allowlist is absent or empty
- **THEN** Alice SHALL log a redacted configuration error identifying the invalid field
- **AND** Alice SHALL continue running without starting CalDAV synchronization

#### Scenario: CalDAV token is mapped to Flutter
- **WHEN** Rust maps loaded configuration for Flutter
- **THEN** Alice SHALL expose whether CalDAV is configured and the non-secret settings needed by the UI
- **AND** Alice SHALL NOT expose the inline token to Flutter unless a native request API strictly requires it

#### Scenario: CalDAV configuration error is logged
- **WHEN** an error string contains the configured token or an authorization header
- **THEN** Alice SHALL redact the secret before writing the log
