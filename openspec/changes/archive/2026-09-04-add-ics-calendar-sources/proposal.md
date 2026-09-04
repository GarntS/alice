## Why

Alice currently supports only one Google Calendar configuration and starts its calendar polling only after the clock panel is opened. Users cannot display local or subscribed iCalendar feeds, and ICS alarms/reminders cannot notify them while the panel is closed.

## What Changes

- Replace the single Google credential shape with a required list of uniquely identified, typed calendar entries.
- Add `ics` entries backed by exactly one local file path or HTTP(S) URL, each with independent refresh cadence, optional display color, and event-notification settings.
- Run configured calendar sources from application startup, merge their events into the clock panel, and retain usable ICS data across refresh failures.
- Add ICS recurrence expansion, VALARM notifications, and the default timed-event reminders at 30, 10, and 2 minutes before an event.
- **BREAKING** Remove support for the legacy single-Google `calendar` configuration; users must migrate to `calendar.calendars` entries.

## Capabilities

### New Capabilities
- `ics-calendar-sources`: Configured local and remote iCalendar feeds, event normalization, recurrence expansion, refresh behavior, colors, and stale-cache behavior.
- `ics-calendar-notifications`: ICS VALARM and default timed-event reminder scheduling and de-duplication through Alice notifications.

### Modified Capabilities
- `clock-world-clock-calendar`: Present events and calendar indicators from every configured calendar source, rather than Google only.
- `configuration`: Define the typed multi-calendar configuration, defaults, validation, and removal of the legacy Google-only form.
- `freedesktop-notifications`: Admit internally generated calendar notifications into Alice's notification service.

## Impact

- Rust calendar configuration, Google OAuth/token storage, event cache/runtime services, iCalendar parsing, notification service, and Flutter/Rust bridge models.
- Clock panel fetch and indicator behavior, default config template, README documentation, and configuration tests.
- A recurrence-expansion library or equivalent implementation will be required in addition to the existing `icalendar` parser.
