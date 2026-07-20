## Context

`calendar.rs::do_fetch_events` maps each full-fetch API event into `(NaiveDate, CalendarEvent)`. `do_poll_incremental` independently repeats ID, title fallback, date extraction, all-day detection, labels, and calendar metadata mapping after handling cancellation. Both feed the same `EventCache.entries` representation.

## Goals / Non-Goals

**Goals:**
- Define one event-to-cache mapping policy.
- Use it in both verified ingestion paths.
- Test mapping without network or OAuth.

**Non-Goals:**
- Changing auth state, runtimes, token storage, API query windows, sync tokens, polling, cancellation semantics, sorting, cache structures, statuses, or Dart APIs.
- Introducing a parser/AST or new dependency.

## Decisions

### Extract a pure mapper

Add a private helper conceptually shaped as:

```rust
fn map_event(
    event: &google_calendar3::api::Event,
    calendar_name: &str,
    calendar_color: &str,
) -> Option<(chrono::NaiveDate, CalendarEvent)>
```

It owns ID defaulting, `"(No title)"`, `extract_event_date`, `extract_time_labels`, and cloning calendar metadata. Taking a reference lets incremental code inspect cancellation and ID before mapping without extra ownership conversions.

Alternative: add `From<Event>` or a wrapper type. Rejected because mapping also requires external calendar metadata and may fail when no start date exists.

### Keep path-specific lifecycle outside the mapper

Full fetch remains responsible for API iteration and insertion. Incremental sync remains responsible for removing prior IDs, skipping cancelled events, updating tokens, and re-sorting. The mapper does not mutate cache state or interpret cancellation.

### Add local API-model tests

Construct `google_calendar3::api::Event` values in unit tests for timed, all-day, missing-title, and missing-start cases. Assert the exact existing output fields. No live calendar credentials or token path may be used.

## Risks / Trade-offs

- **Generated Google API structs are awkward to construct** → Use `Default` plus only relevant fields; keep tests private to `calendar.rs`.
- **Incremental cancellation accidentally enters mapper** → Keep status check and prior-entry removal visibly in `do_poll_incremental`.
- **Timezone-sensitive labels** → Build fixed UTC timestamps and assert according to the existing local conversion contract only where deterministic; otherwise isolate label-format assertions appropriately.

## Migration Plan

Refactor both call sites in one commit and run tests. Cache is process-local, so no persisted migration or rollout ordering is required.

## Open Questions

None. Dynamic Google API behavior remains covered by existing error handling and is outside this structural refactor.
