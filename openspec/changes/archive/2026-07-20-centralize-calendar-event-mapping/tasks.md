## 1. Shared Event Mapper

- [x] 1.1 Add a private pure helper in `native/alice_platform/src/calendar.rs` that maps `&google_calendar3::api::Event` plus calendar name/color to `Option<(NaiveDate, CalendarEvent)>`.
- [x] 1.2 Move existing id defaulting, `"(No title)"` fallback, date extraction, all-day detection, local-time label extraction, and metadata cloning into that helper without changing outputs.

## 2. Integrate Both Ingestion Paths

- [x] 2.1 Replace the duplicated mapping block in `do_fetch_events` with the shared helper.
- [x] 2.2 Replace the duplicated mapping block in `do_poll_incremental` with the same helper while keeping prior-id removal and cancellation checks outside it.
- [x] 2.3 Preserve cache window boundaries, calendar-list behavior, unreadable-calendar skipping, sync tokens, cache invalidation, sorting, polling, auth/token state, and result status strings.

## 3. Hermetic Mapping Tests

- [x] 3.1 Add unit tests using local Google API `Event` values for timed and all-day mappings, including exact id/title/date/labels/calendar metadata.
- [x] 3.2 Add tests for missing-title fallback and missing-start rejection without network, credentials, token files, or environment-dependent config.
- [x] 3.3 Add or retain coverage proving cancelled incremental events are removed and not reinserted if that can be tested without broad cache/global-state coupling; otherwise keep the control flow explicit and document the test limit.
- [x] 3.4 Search `calendar.rs` and confirm exactly one construction policy for cached `CalendarEvent` values remains.
- [x] 3.5 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform` and confirm no FRB/generated/Dart files changed.
- [x] 3.6 Run `openspec validate centralize-calendar-event-mapping --strict`.
