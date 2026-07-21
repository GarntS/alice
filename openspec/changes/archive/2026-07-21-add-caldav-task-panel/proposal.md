## Why

Alice has no actionable task view, so due work stored in Vikunja is invisible from the bar and must be managed in a separate application. A CalDAV-backed task module and panel will make overdue and current work visible and allow safe completion toggles while establishing a reusable CalDAV foundation for future event features.

## What Changes

- Add an optional, typed CalDAV account configuration with principal URL, an HTTP transport opt-in defaulting to false, username, inline token, collection-href allowlist, polling interval, and optional custom CA certificate.
- Discover allowed CalDAV collections and synchronize VTODO and VEVENT resources into a persisted Rust cache, using incremental sync when available and bounded full-sync fallbacks.
- Normalize VTODO due dates, completion state, collection identity, and five Vikunja-compatible priorities: Do Now, Urgent, High, Medium, and Low.
- Add optimistic, ETag-protected task completion and un-completion while preserving unrelated iCalendar resource data and reverting failed writes.
- Add task state and derived overdue/today counts to the Rust snapshot and granular Flutter snapshot state.
- Add a compact top-bar task module before the clock and a scrollable task panel grouped by due date, priority, undated state, and completion today.
- Parse and cache VEVENT resources for a rolling three-month past/future window, preserving recurrence metadata without exposing events in the UI or expanding occurrences yet.
- Preserve cached task visibility across restarts and expose explicit loading, stale, synchronization-error, and empty states.

## Capabilities

### New Capabilities
- `caldav-sync`: CalDAV configuration, collection discovery, task/event synchronization, persistence, date and priority normalization, and conflict-safe completion writes.
- `task-panel`: Top-bar due-state presentation and the grouped, interactive task panel UX.

### Modified Capabilities
- `configuration`: Add the optional typed CalDAV configuration contract and documented defaults.
- `snapshot-runtime`: Add cached CalDAV task state and synchronization triggers to the Rust snapshot runtime.
- `snapshot-state`: Add granular task slices and derived overdue/today projections without weakening rebuild isolation.
- `bar-shell-layout`: Insert the optional task module before the clock in the right-side module order.
- `panel-controller`: Add the task panel identity, open-state listener, sizing, highlighting, and native bridge mapping.

## Impact

- Rust native platform: new CalDAV HTTP/WebDAV, XML, iCalendar, cache, and synchronization code; runtime integration; public bridge models and completion actions.
- Flutter: generated bridge updates, typed configuration mapping, granular snapshot state, task bar module, task panel, panel registry/sizing, and application callbacks.
- Configuration and storage: new `caldav` YAML section, optional private CA path, inline secret-handling requirements, and a mode-restricted cache under Alice's XDG directories.
- Dependencies: production-quality HTTP/WebDAV, XML, and iCalendar parsing support may require new Rust crates.
- Existing Google Calendar behavior remains separate and unchanged; CalDAV VEVENT data has no UI in this change.
