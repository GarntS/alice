## Why

Outlook ICS feeds use Windows timezone identifiers such as `Eastern Standard Time`. Alice currently reduces their embedded timezone definitions to a fixed standard offset, making daylight-saving events—including the 2026-10-05 12:30 event—appear and trigger reminders an hour late.

## What Changes

- Resolve recognized Windows timezone IDs using ICU4X's maintained CLDR mappings, then use `chrono-tz` for date-specific offsets.
- Apply resolution consistently to ICS event starts, ends, recurrence dates, exclusions, detached exceptions, and timezone-qualified absolute alarms.
- Keep existing UTC, IANA, floating-time, all-day, and unrecognized-zone behavior compatible; full custom VTIMEZONE evaluation is out of scope.
- Add deterministic summer/winter and recurrence regression coverage.
- Correct existing generated recurrence end times and relative alarm duration parsing bugs exposed by regression coverage.
- Verify development, packaging, and CI Rust compatibility; update Rust tooling only where required by the selected ICU dependency.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ics-calendar-sources`: Recognized Windows timezone identifiers resolve to date-aware named zones rather than embedded fixed offsets.

## Impact

- Native ICS parsing and normalization in `native/alice_platform/src/calendar_sources.rs`.
- ICU4X Rust dependency (prefer the focused `icu_time` crate), native manifests and lockfile.
- Calendar parsing tests and synthetic fixtures; no private feed URLs or event identity in fixtures.
- Rust development, Nix packaging, and release CI tooling if their versions are insufficient.
- No Flutter bridge, configuration schema, or UI API changes; CalDAV parsing is outside this change.
