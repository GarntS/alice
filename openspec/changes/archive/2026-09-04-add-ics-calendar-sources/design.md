## Context

The current calendar module is a Google-only, process-global fetch cache with one OAuth token path. It begins its incremental polling after a clock-panel request. The CalDAV parser can parse VEVENT structures and time zones but deliberately does not expand recurrences. The notification server already owns Alice's in-memory notification store and snapshot trigger.

## Goals / Non-Goals

**Goals:**
- Make calendar sources independently refreshable, source-scoped, and available before panel access.
- Keep existing Google authorization UX while allowing distinct OAuth state and token storage for every Google entry.
- Normalize Google and ICS occurrences into the existing calendar event contract.
- Deliver ICS alarms and event reminders through the existing notification UI reliably and without duplicate refresh-triggered notices.

**Non-Goals:**
- CalDAV calendar-event synchronization, editing ICS data, or write access to any calendar.
- VALARM repeat cycles, all-day default reminders, and notification actions.
- Supporting URL schemes other than HTTP(S), or legacy single-Google configuration migration.

## Decisions

### Typed source list with stable identities
`calendar.calendars` is the only accepted configuration form. Entries have a required unique `id`, discriminated `type`, common interval/color fields, and type-specific fields. The ID scopes runtime caches and prevents two Google accounts with the same OAuth client ID from sharing a token. Each Google token is stored under an ID-specific path; changing an ID intentionally requires authorization again.

The Rust-to-Flutter configuration remains secret-free: Flutter needs to know that sources are configured, but no OAuth secret is bridged. Google initialization remains lazy when user authorization is required, because the device-flow URL and code are displayed in the clock panel.

### Calendar runtime coordinator
A startup-owned coordinator creates one refresh worker per enabled source. Each worker writes source-scoped normalized occurrences into a merged, synchronized event store. Date requests read that merged store and do not initiate source polling. The coordinator refreshes immediately, then at the entry's interval; a failed ICS refresh retains that source's prior snapshot. Google continues to use incremental sync where possible, with source-specific authentication/cache state.

This replaces the current panel-owned polling lifecycle. It also ensures the reminder scheduler runs when the panel is closed.

### ICS parsing and recurrence window
Use the existing iCalendar parser for component/property parsing and add a recurrence evaluator capable of expanding RRULE and RDATE within the rolling event window, excluding EXDATE and applying detached RECURRENCE-ID overrides. Keep normalized occurrence identities as `(source id, UID, recurrence start)` so cache replacement and notification de-duplication survive refreshes.

Event time values are resolved to instants using UTC, IANA TZID, embedded VTIMEZONE definitions, or the machine local zone for floating values. Invalid events are skipped with a source-scoped diagnostic rather than discarding other valid events.

### Colors and display metadata
An ICS entry uses its configured color or the fixed red fallback. A Google entry's configured color is only a fallback: individual Google Calendar API colors win. Source IDs provide a stable fallback label when ICS calendar metadata is missing.

### In-process notification injection
Expose a narrow notification-store helper for Alice-originated notifications rather than sending D-Bus calls to Alice's own server. It creates canonical unread notification payloads and emits the ordinary snapshot trigger, preserving existing panel and popup behavior.

The reminder scheduler recomputes upcoming notification identities after every source update. It maintains a bounded set of delivered identities and schedules only future triggers. A VALARM creates one notification for its first trigger even if `REPEAT` is present. Default reminders apply only to timed ICS occurrences when `notify_for_events` is true.

## Risks / Trade-offs

- [Remote feeds can be unavailable or malformed] → Retain last usable snapshot, isolate failures by source, and log non-sensitive diagnostics.
- [Recurrence rules and time zones are complex] → Bound expansion to the rolling window, test daylight-saving transitions, exceptions, and embedded time zones with fixtures.
- [A source discovered after a reminder time could produce stale noise] → Never emit already-past trigger identities.
- [Refreshes or recurring expansion can duplicate notifications] → Use the source/UID/occurrence/reminder identity as the sole scheduler key.
- [Multiple Google OAuth flows can contend for user attention] → Keep authorization state, token path, and panel status per source; allow a source's pending authorization not to block ICS sources.

## Migration Plan

1. Ship the new default template and README examples using `calendar.calendars`.
2. Treat the legacy credential layout as unsupported and log a migration-oriented configuration error without enabling it.
3. On rollback, users must restore the prior single-Google configuration because legacy parsing is intentionally removed.
