## Context

Alice is a Flutter Wayland bar whose native data collection and system interactions live in Rust. Rust emits one debounced `BarSnapshot`; `AliceSnapshotState` then exposes granular listenable slices so unrelated modules do not rebuild. Panels have canonical ids, fixed size policies, and a single-open-panel controller. The existing `calendar.rs` is a Google-specific, read-only, panel-triggered integration and does not provide a reusable CalDAV client or writable task state.

Vikunja exposes projects as CalDAV collections under a user principal, serializes tasks as VTODO, maps its five non-zero priorities onto RFC 5545 `PRIORITY`, and supports RFC 6578 `sync-collection` in current releases. CalDAV resources can also contain VEVENT, unknown properties, alarms, recurrence data, and timezone definitions that Alice must not destroy when changing completion state.

The task module needs current counts while its panel is closed, so synchronization belongs in the Rust snapshot runtime rather than in the Flutter panel lifecycle. The user selected one optional account, an explicit collection-href allowlist, inline token authentication, a configurable 60-second default poll, local-date semantics, persisted offline state, and a bounded event cache with no event UI.

## Goals / Non-Goals

**Goals:**

- Keep allowed CalDAV collections synchronized in a runtime-owned, persisted cache.
- Represent both VTODO and VEVENT while exposing only task data in this change.
- Normalize tasks into deterministic local-date, priority, status, and source fields.
- Complete and un-complete tasks without discarding unrelated iCalendar data or overwriting concurrent edits.
- Drive a compact bar module and grouped task panel through the existing snapshot and granular-state architecture.
- Preserve useful cached tasks across restarts and make loading, stale, and error state explicit.
- Keep credentials, cached resources, and logs appropriately protected.

**Non-Goals:**

- Creating, editing, deleting, expanding, or opening task details.
- Rendering CalDAV events or merging them into the existing Google Calendar panel.
- Expanding recurring VEVENT instances.
- Queuing task mutations while offline.
- Supporting multiple CalDAV accounts in the first version.
- Replacing the existing Google Calendar implementation with a common calendar repository.

## Decisions

### 1. Add a runtime-owned CalDAV service and cache

Create a native CalDAV module with three boundaries: a protocol client, pure iCalendar normalization/mutation helpers, and a synchronized cache. The snapshot runtime owns the service, starts it only when valid CalDAV configuration exists, reads cache state without network I/O during snapshot assembly, and receives triggers whenever synchronization or a confirmed mutation changes that cache.

```text
poll / refresh / mutation
          │
          ▼
┌─────────────────────┐
│ CalDAV protocol     │ discovery, REPORT, GET, PUT
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ parser + normalizer │ VTODO / VEVENT / VTIMEZONE
└──────────┬──────────┘
           ▼
┌─────────────────────┐    trigger    ┌─────────────┐
│ runtime cache       │──────────────▶│ BarSnapshot │
└─────────────────────┘               └─────────────┘
```

This follows the cached MPRIS and weather provider pattern and avoids network work whenever an unrelated one-second stats trigger fires. Panel-only fetching was rejected because the bar must remain current while the panel is closed. Putting WebDAV in Dart was rejected because native integrations and credentials belong in Rust in this project.

### 2. Use an optional typed `caldav` configuration

The configuration contains `principal_url`, `allow_http` defaulting to false, `username`, inline `token`, `collection_hrefs`, `poll_interval_secs` defaulting to 60 and clamped to at least 1, and optional `ca_certificate_path`. An absent section disables synchronization and removes the task module. A present section with missing required values logs a redacted configuration error and leaves the rest of Alice running.

Collection hrefs are canonicalized against the principal origin and compared as normalized URLs. Alice rejects cross-origin collection hrefs and does not forward authorization across cross-origin redirects. HTTPS is required unless `allow_http` is explicitly true; this opt-in permits cleartext credentials for trusted test networks but does not weaken same-origin enforcement. For HTTPS, system trust roots remain mandatory unless the optional custom CA successfully loads; there is no insecure-verification mode.

Inline configuration was chosen to match the requested deployment model and Alice's existing Google credential approach. The shipped documentation will require restrictive config permissions, and token values must never appear in debug output, error text, cache keys, or generated snapshots.

### 3. Discover capabilities, then prefer incremental collection synchronization

Alice performs principal/calendar-home discovery, obtains collection display names and supported component sets, and retains only collections whose canonical href appears in the allowlist. For Vikunja, the discovered calendar home is `/dav/projects/`, individual project collections are `/dav/projects/<project-id>`, and task resources are children named by UID. Collection allowlist comparison treats server-advertised forms with and without a trailing slash as equivalent while requests retain the server-advertised href. A configured href that is absent or not readable becomes a visible synchronization error without preventing other allowed collections from synchronizing.

Per collection, Alice persists ETags and an RFC 6578 sync token. It prefers `sync-collection`; an empty/invalid token causes a bounded full synchronization, and a server response indicating `valid-sync-token` recovery clears only that collection's token. Servers without incremental support use CalDAV `calendar-query`/multiget or equivalent bounded full synchronization. Removed resources are evicted. One failed collection does not discard successful data from other collections.

The normal background cadence is configurable with a 60-second default. Alice also requests synchronization at startup, when the task panel opens, on manual refresh, and when the local date rolls over enough to shift the VEVENT cache window. Concurrent refresh requests coalesce into one in-flight pass.

### 4. Persist cache state atomically and expose freshness separately from data

Persist normalized records, resource hrefs, ETags, sync tokens, collection metadata, recurrence/timezone metadata, and the lossless resource text needed for safe mutation under Alice's XDG cache directory. Write a temporary file, fsync/close it, and atomically replace the cache; apply mode `0600`. Parse/version failures quarantine or ignore the cache and force a full synchronization rather than failing application startup.

On startup, cached records are published immediately as stale until a live synchronization succeeds. The snapshot carries task records plus synchronization status, last successful synchronization time, and a redacted error message. During an error, the bar replaces counts with an error indication; the panel continues to show cached rows under an error/stale banner. Without cached data, the panel shows the error alone.

A memory-only cache was rejected because it would make startup counts unavailable offline and force full synchronization after every restart. Silently displaying stale counts was rejected by the selected UX.

### 5. Normalize task dates, statuses, and priorities in Rust

For `VALUE=DATE`, preserve the calendar date exactly. For DATE-TIME values, honor UTC or TZID semantics, convert to the machine's local timezone, then retain only `YYYY-MM-DD` for due grouping. Convert `COMPLETED` to local time for the completed-today boundary and retain its instant only for sorting; Flutter never renders its time.

Normalize VTODO status as follows:

- `NEEDS-ACTION`, `IN-PROCESS`, or absent: active.
- `COMPLETED`: completed.
- `CANCELLED`: hidden.

Normalize RFC priority as `1 = Do Now`, `2 = Urgent`, `3..4 = High`, `5 = Medium`, and `0`, absent, or `6..9 = Low`. Invalid reserved values fall back to Low without aborting the collection. Missing summaries use a stable `(No title)` fallback.

Active dated tasks sort by due date ascending, normalized priority, case-insensitive title, then href. Undated tasks sort by priority, title, then href. Tasks completed on the current local date sort by completion instant descending, priority, title, then href and appear only in the terminal completed section. Other completed tasks are not presented.

### 6. Preserve full resources and use ETag-guarded completion writes

The checkbox action identifies a resource by canonical collection/resource href. Alice patches the latest lossless VTODO rather than serializing only displayed fields:

- Complete: set `STATUS:COMPLETED`, set `COMPLETED` to the current UTC instant, and set `PERCENT-COMPLETE:100`.
- Un-complete: set `STATUS:NEEDS-ACTION`, remove `COMPLETED`, and set `PERCENT-COMPLETE:0`.

It preserves UID, due/start values, recurrence, alarms, descriptions, labels, relationships, unknown properties, and sibling VCALENDAR components. PUT uses `If-Match` with the cached ETag. A precondition failure refetches the latest resource, reapplies the requested completion state, and retries once; subsequent conflict or transport failure returns an error. A success updates the cache from the authoritative response or a follow-up GET and emits a snapshot trigger.

Flutter moves the row optimistically and disables its checkbox while the future is pending. Failure removes the optimistic override, restores the snapshot-backed row, and shows an action error. Mutations are not queued offline.

### 7. Parse bounded VEVENT records without occurrence expansion

Allowed event-capable collections synchronize VEVENT resources intersecting a rolling window from three months before through three months after the current local date. The cache retains base event fields, all-day/timed date information, RRULE/RDATE/EXDATE, RECURRENCE-ID exceptions, and referenced VTIMEZONE definitions. It does not materialize recurrence occurrences or expose events through Flutter in this change.

This establishes lossless protocol support while avoiding an untested recurrence engine with no consumer. Storing only raw VEVENT text was rejected because it would not establish a typed event integration; eager expansion was rejected because correct recurrence behavior is a separate substantial capability.

### 8. Extend snapshots and keep Flutter projections granular

Add task synchronization state and normalized task records to `BarSnapshot`. `AliceSnapshotState` performs content-aware task comparison and exposes independent raw task/sync-state listenables plus derived overdue and today counts. It recomputes date-relative projections when tasks change and when the local clock crosses a date boundary, without notifying task consumers for unrelated CPU, media, weather, tray, or notification changes.

The top-bar module consumes only due projections and synchronization state. The task panel consumes the task list and synchronization state. Pending checkbox overrides remain local to the panel/action owner and do not alter the persisted snapshot until Rust confirms the server write.

### 9. Add a canonical task panel and compact bar module

Add `tasks` as a canonical panel id with a stable open-state listenable, right alignment, fixed width 380, and a content-sized surface capped at a scrollable height of 800. Insert its bar module immediately before the clock whenever CalDAV is configured.

The bar shows an icon plus non-zero today and overdue counts, with overdue visually distinct. When both values are zero it shows only the icon. Synchronization failure replaces counts with an error symbol; activating any state opens the panel.

The panel renders human date headers (`Today - 20 July`, adding a year only outside the current year), one block per overdue/future date, an undated block, and a final completed-today block. `Today -`, day numbers, and years use bold black text while full month names use bold configured-accent text; date headers have no calendar icons and use slightly enlarged type with compact spacing, vertically centered against the right-justified task count. The configured accent color also ties together the heading and a compact single-row metric summary whose icons and numbers are semantically colored while its Active/Today/Overdue labels remain black. Inner task-panel elements remain flat, without card fills or borders. Every task uses a light checkbox outline, medium-weight title, and smaller named colored priority text plus muted collection metadata so priority is not color-only. Do Now and Urgent are red, High is orange, Medium is green, and Low/unprioritized is blue. Completed rows are grayed out. Last-success metadata remains in a typographically muted footer below the task content. Only the checkbox is interactive; panel open and manual refresh request immediate synchronization.

## Risks / Trade-offs

- [Vikunja emits UTC DATE-TIME due values that may shift across local date boundaries] → Test UTC, explicit TZID, floating, and date-only values around midnight and document Alice's selected local-date rule.
- [CalDAV and iCalendar interoperability is broad] → Use maintained parsers, disable external XML entities/DTD resolution, preserve unknown data losslessly, and add fixture tests from Vikunja plus standards-oriented edge cases.
- [A malformed mutation could destroy unrelated task metadata] → Patch the original component, assert preservation in round-trip tests, use ETags, and refetch after success.
- [Persisted resources and inline credentials are sensitive] → Apply restrictive permissions, never log secrets/resource bodies, keep errors redacted, and document the security implications.
- [Some servers lack or incorrectly implement sync tokens] → Detect capabilities, isolate per-collection state, and retain a bounded full-sync fallback.
- [Polling every 60 seconds may be unnecessary traffic] → Make the interval configurable, use incremental tokens, coalesce overlapping refreshes, and avoid network I/O during snapshot assembly.
- [The top-bar right group is already crowded] → Keep zero states icon-only, omit individual zero counters, use compact chips, and cover constrained-width rendering.
- [Recurring VTODO completion differs by server] → Send a standards-compatible state change and always reconcile from the authoritative server resource.
- [Task content may be very short or exceed the output] → Size the card naturally for short content and cap it at a scrollable 800-pixel maximum using the same loose-constraint pattern as the calendar panel.

## Migration Plan

1. Add dependencies, typed models, configuration, and pure parser/normalizer tests without enabling runtime synchronization when `caldav` is absent.
2. Add versioned cache persistence and protocol tests using local fixtures/mock HTTP; do not contact a live server in automated tests.
3. Extend generated bridge contracts, snapshot runtime/state, panel registry, and Flutter UI.
4. Document the optional configuration and security requirements. Existing users without `caldav` configuration retain identical behavior and see no task module.
5. Validate against a Vikunja test account before release. Rollback consists of removing/commenting the `caldav` section; cached files can remain unused or be deleted safely.

## Open Questions

None. Pixel-level chip colors and final typography may use the existing theme's semantic colors as long as every priority remains text-labeled and visually distinct.
