## 1. Configuration and bridge contracts

- [x] 1.1 Replace the legacy Google-only native calendar configuration with validated typed entries, required unique IDs, type-specific fields, color normalization, 600-second defaults, and ICS reminder defaults.
- [x] 1.2 Update the secret-free Rust/Flutter bridge and Dart configuration models for calendar entry presence and metadata without exposing Google secrets.
- [x] 1.3 Update the shipped config template and README with the new Google and ICS configuration examples and legacy-format migration note.
- [x] 1.4 Add native and Dart configuration tests for valid mixed entries, defaults, invalid entries, duplicate IDs, and rejected legacy form.

## 2. Source runtime and Google isolation

- [x] 2.1 Refactor calendar state into a startup-owned source coordinator with merged, source-scoped event storage and date-query APIs.
- [x] 2.2 Start and stop independent source refresh workers from the runtime lifecycle; preserve last valid ICS data when refreshes fail.
- [x] 2.3 Scope Google authorization state, token paths, event caches, sync tokens, and polling by calendar entry ID while preserving device-flow panel status.
- [x] 2.4 Adapt Google event mapping to preserve remote colors and apply entry color only as a fallback.
- [x] 2.5 Add runtime/coordinator tests for independent source cadence, source failure isolation, merged date results, and source-scoped Google state.

## 3. ICS ingestion and event expansion

- [x] 3.1 Add recurrence-expansion support and implement ICS local-file and HTTP(S) acquisition with source-scoped diagnostics.
- [x] 3.2 Parse ICS calendar metadata, VEVENT time values, embedded or named time zones, and normalize source-scoped occurrence identities.
- [x] 3.3 Expand RRULE/RDATE occurrences in the rolling window while applying EXDATE and detached exceptions.
- [x] 3.4 Map ICS occurrences to the shared calendar event model with configured or fixed-default colors and stable fallback labels.
- [x] 3.5 Add fixtures and tests for files, HTTP feeds, malformed sources, recurring exceptions, all-day events, and daylight-saving/timezone boundaries.

## 4. ICS notifications

- [x] 4.1 Add an internal notification-store entry point that creates canonical unread Alice-originated notifications and triggers snapshot updates.
- [x] 4.2 Parse absolute and relative VALARM triggers and schedule one initial alarm notification per timed occurrence.
- [x] 4.3 Schedule 30-, 10-, and 2-minute default reminders for timed ICS events when `notify_for_events` is enabled.
- [x] 4.4 Implement bounded source/UID/occurrence/reminder de-duplication and suppression of already-past triggers across refreshes and startup.
- [x] 4.5 Add scheduler and notification-store tests for due alarms, disabled reminders, all-day exclusions, repeated VALARM handling, stale triggers, and duplicate refreshes.

## 5. Clock panel integration and verification

- [x] 5.1 Update calendar fetching, indicators, and status handling to consume merged source events while retaining existing request-ownership behavior.
- [x] 5.2 Update clock-panel tests for multi-source event presentation and color indicators.
- [x] 5.3 Run Rust and Flutter test suites, formatter/linter checks, and strict OpenSpec validation.
