## Why

Full Google Calendar fetches and incremental sync currently duplicate the policy for mapping API events into cached `CalendarEvent` values. One mapping function prevents the two ingestion paths from drifting while preserving cache, sorting, and presentation behavior.

## What Changes

- Extract a single helper that converts a Google API event plus calendar name/color into an optional `(NaiveDate, CalendarEvent)`.
- Use that helper from both initial multi-month fetch and incremental synchronization.
- Keep cancellation removal, sync-token handling, cache windowing, sorting, local-time labels, missing-title fallback, and error statuses unchanged.
- Add focused mapping tests for timed, all-day, missing-title, and missing-start cases.

## Capabilities

### New Capabilities

### Modified Capabilities
- `clock-world-clock-calendar`: Require full and incremental event ingestion to apply one consistent event-mapping policy without changing returned event behavior.

## Impact

- Affected implementation and tests: `native/alice_platform/src/calendar.rs`.
- Public API: `fetch_calendar_events`, `CalendarEvent`, `CalendarFetchResult`, status strings, and Dart call sites remain unchanged.
- Persistence/authentication: token path, OAuth flow, credentials, sync tokens, and calendar cache format remain unchanged.
- Dependencies and generated files: unchanged.
