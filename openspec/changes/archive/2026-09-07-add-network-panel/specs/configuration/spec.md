## MODIFIED Requirements

### Requirement: Supported configuration model
Alice SHALL expose typed configuration for theme mode, accent color, transparent top bar preference, panel gap, tray visibility limit, local and additional time zones, power commands, an optional list of typed calendar entries, optional CalDAV account settings, notification settings, and weather settings. Each calendar entry SHALL have a unique `id`, a `type` of `google` or `ics`, an optional `#RRGGBB` `color`, and an effective `poll_interval_secs` of 600 when omitted. Google entries SHALL contain Google OAuth client credentials. ICS entries SHALL contain exactly one local `path` or HTTP(S) `url` and SHALL default `notify_for_events` to true.

#### Scenario: Typed config is loaded by Flutter
- **WHEN** Flutter calls `loadConfig`
- **THEN** Rust SHALL return the typed configuration over flutter_rust_bridge
- **AND** Flutter SHALL map theme modes, colors, transparent top bar preference, time zones, power commands, panel gap, calendar entry presence, CalDAV presence and settings, notification settings, and weather settings into its UI configuration model

#### Scenario: Calendar entry defaults are omitted
- **WHEN** a valid calendar entry omits `poll_interval_secs`, `color`, or, for an ICS entry, `notify_for_events`
- **THEN** Alice SHALL use a 600-second polling interval
- **AND** Alice SHALL preserve the absence of an entry color for source-specific color fallback
- **AND** Alice SHALL treat `notify_for_events` as true

#### Scenario: Invalid calendar entry is configured
- **WHEN** a calendar entry has a duplicate or empty id, an unsupported type, an invalid color, a non-positive interval, or does not satisfy its type-specific required fields
- **THEN** Alice SHALL reject that entry without exposing it as an enabled calendar source

#### Scenario: Legacy Google calendar form is configured
- **WHEN** `calendar` contains the former top-level Google credential fields instead of `calendar.calendars`
- **THEN** Alice SHALL NOT enable that legacy calendar configuration

#### Scenario: Notification popup config is omitted
- **WHEN** the YAML omits `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL default `show_notification_popup` to `true`
- **AND** Alice SHALL default `notification_display_time_ms` to `5000`
- **AND** Alice SHALL default `expire_critical_notifications` to `false`

#### Scenario: Notification popup config is provided
- **WHEN** the YAML provides `notifications.show_notification_popup`, `notifications.notification_display_time_ms`, or `notifications.expire_critical_notifications`
- **THEN** Alice SHALL expose those values in the typed configuration model returned to Flutter
