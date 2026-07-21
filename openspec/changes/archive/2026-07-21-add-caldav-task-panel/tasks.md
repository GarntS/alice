## 1. Native Models, Dependencies, and Configuration

- [x] 1.1 Select maintained Rust HTTP/WebDAV, XML, URL, and iCalendar parsing dependencies that support custom CA roots, safe XML parsing, lossless property preservation, and fixture-based tests; update native manifests and lockfiles.
- [x] 1.2 Add typed Rust `CalDavConfig` parsing for principal URL, false-by-default HTTP opt-in, username, inline token, collection hrefs, 60-second polling default/minimum, and optional CA certificate path.
- [x] 1.3 Add CalDAV configuration validation, URL/href canonicalization, same-origin checks, and reusable token/authorization redaction helpers with unit tests.
- [x] 1.4 Extend the shipped commented default config, Dart `AliceConfig` mapping, test helpers, and configuration contract tests without exposing the token to Flutter.
- [x] 1.5 Define native collection, lossless resource, normalized task, typed event, recurrence/timezone, priority, and synchronization-state models with deterministic equality/serialization behavior.

## 2. iCalendar Parsing and Mutation

- [x] 2.1 Implement pure VTODO parsing for folded/escaped text, stable href/UID/title/source fields, status normalization, and cancelled-task hiding using local fixtures.
- [x] 2.2 Implement date-only and UTC/TZID/floating DATE-TIME normalization for `DUE` and `COMPLETED`, including local-midnight boundary tests and no user-visible time fields.
- [x] 2.3 Implement the five-level priority mapping, missing-title fallback, active/completed classification, and deterministic dated/undated/completed ordering with unit tests.
- [x] 2.4 Implement typed VEVENT parsing for the bounded event model, including all-day/timed fields, RRULE/RDATE/EXDATE, RECURRENCE-ID exceptions, and referenced VTIMEZONE preservation without occurrence expansion.
- [x] 2.5 Implement lossless complete/un-complete VTODO patching for STATUS, COMPLETED, and PERCENT-COMPLETE while preserving unrelated properties, components, alarms, relationships, recurrence, descriptions, and unknown extensions.
- [x] 2.6 Add Vikunja-derived and standards-oriented round-trip fixtures proving parsing and completion patching preserve all non-completion content.

## 3. CalDAV Protocol Client

- [x] 3.1 Build the authenticated client with HTTPS by default, explicit HTTP opt-in, system roots, optional custom CA loading, hostname verification, same-origin redirect protection, safe XML settings, and redacted errors.
- [x] 3.2 Implement principal/calendar-home discovery, including Vikunja `/dav/projects` collections and trailing-slash equivalence, collection metadata/capability parsing, canonicalize returned hrefs, and filter strictly to the configured allowlist.
- [x] 3.3 Implement initial VTODO and bounded ±3-month VEVENT query/multiget synchronization, including collection isolation, ETag capture, deletion reconciliation, and collection display names.
- [x] 3.4 Implement RFC 6578 `sync-collection` updates with per-collection tokens, changed resource application, deletion handling, invalid-token reset, and full-sync fallback.
- [x] 3.5 Implement non-incremental bounded reconciliation for servers without usable sync tokens and event-window reconciliation when the local date changes.
- [x] 3.6 Implement task PUT with `If-Match`, one refetch/repatch retry on precondition failure, authoritative response reconciliation, and transport/conflict failure reporting.
- [x] 3.7 Add hermetic mock-server protocol tests for discovery, allowlist rejection, authentication, custom CA behavior where practical, incremental updates, token invalidation, deletion, partial collection failure, and ETag conflicts.

## 4. Persistent Cache and Runtime Service

- [x] 4.1 Implement a versioned CalDAV cache path under Alice's XDG cache directory with atomic replacement, mode `0600`, invalid-version recovery, and no credential persistence.
- [x] 4.2 Persist and reload collection metadata, lossless resources, normalized tasks/events, ETags, sync tokens, event-window bounds, freshness, and last-success state with round-trip and corruption tests.
- [x] 4.3 Implement a concurrency-safe runtime CalDAV cache/provider whose reads perform no network I/O and whose updates report whether snapshot-visible state changed.
- [x] 4.4 Add startup synchronization, configurable polling, panel/manual refresh requests, date-window rollover, and coalescing of concurrent refresh requests to the Tokio runtime.
- [x] 4.5 Keep successful collection data when another collection or poll fails, publish cached startup data as stale, and expose current/loading/error/last-success state through redacted models.
- [x] 4.6 Wire confirmed completion mutations and synchronization changes to cache persistence and debounced runtime snapshot triggers; leave failed/offline mutations unqueued.
- [x] 4.7 Add fake-provider/runtime tests proving unrelated snapshot triggers do not perform CalDAV I/O and CalDAV failures do not stop other providers or discard cached tasks.

## 5. Bridge and Granular Snapshot State

- [x] 5.1 Extend Rust `BarSnapshot` and public FRB exports with normalized tasks and CalDAV synchronization state while keeping VEVENT records and credentials native-only.
- [x] 5.2 Add native bridge actions for coalesced CalDAV refresh and complete/un-complete operations with stable task resource identity and redacted failures.
- [x] 5.3 Regenerate Rust/Dart flutter_rust_bridge bindings and update bridge/config test fixtures for every new model and action.
- [x] 5.4 Extend `AliceSnapshotState` with content-aware task and synchronization-state comparators, raw listenables, current values, disposal, and snapshot reconstruction.
- [x] 5.5 Add independently listenable due-today and overdue projections that exclude completed/cancelled/undated tasks and recompute on task changes and local-date rollover.
- [x] 5.6 Add snapshot-state tests for equivalent task list identity, content changes, status-only changes, count stability, midnight rollover, and isolation from CPU/media/weather/tray/notification updates.

## 6. Panel Registry and Top-Bar Module

- [x] 6.1 Add canonical `tasks` panel identity, parser round-trip, stable open-state accessor, right-aligned anchor behavior, and content-sized `380x800` scrollable maximum policy.
- [x] 6.2 Extend panel host/application callback plumbing for task refresh and completion actions without changing existing panel behavior.
- [x] 6.3 Build the compact task bar module with named accessibility semantics, panel highlight, non-zero today/overdue counts, distinct overdue styling, icon-only zero state, and error replacement state.
- [x] 6.4 Insert the configured task module immediately before the clock and omit it entirely when valid CalDAV configuration is absent.
- [x] 6.5 Add controller, panel-command, sizing, consistent reduced panel-card top inset, top-bar order, constrained-width rendering, zero/error state, and granular highlight-rebuild tests for the new module/panel.

## 7. Task Panel and Interactions

- [x] 7.1 Build pure Flutter grouping/sorting helpers for overdue date blocks, today, future dates, no due date, and newest-first completed today using the specified tie-breakers.
- [x] 7.2 Build compact, slightly enlarged, icon-free typographic date headers with bold black prefixes/day/year, full bold accent month names, and a vertically centered right-justified task count, omitting the current year and never rendering due or completion times.
- [x] 7.3 Build flat task rows with light checkbox outlines, medium-weight titles, always-visible smaller muted collection sources, red Do Now/Urgent, orange High, green Medium, blue Low/unprioritized named text, and grayed completed styling without inner card fills or borders.
- [x] 7.4 Build the content-sized scrollable panel shell with flat accent heading, compact one-row colored-icon/number and black-label summary, refresh control, loading, current-empty, stale-cache, synchronization-error, action-error, and bottom last-success footer.
- [x] 7.5 Request refresh when the panel opens and on manual action, and disable/coalesce the UI refresh control while a request is pending.
- [x] 7.6 Implement per-task optimistic completion overrides, pending checkbox disabling, immediate section movement, authoritative snapshot reconciliation, and failure reversion without making non-checkbox row areas interactive.
- [x] 7.7 Add widget tests for visual hierarchy, content sizing, footer placement, all section ordering, five priority levels, source labels, date formats, completed-today filtering/order, no-time presentation, long/empty lists, and scroll bounds.
- [x] 7.8 Add widget tests for complete/un-complete success, duplicate-click prevention, failure rollback, panel-open/manual refresh, stale cached display, and local-date rollover.

## 8. Documentation and Verification

- [x] 8.1 Document Vikunja principal URL discovery, dedicated token creation, inline token security, collection href allowlisting, false-by-default HTTP opt-in, custom CA usage, polling defaults, cache location, and task/event scope in README and the default config comments.
- [x] 8.2 Verify logs, snapshots, errors, cache metadata, tests, and fixtures never expose configured credentials or authorization headers; verify cache/config permission guidance.
- [x] 8.3 Run native formatting and linting, focused CalDAV/config/runtime unit and mock-server tests, and the complete Rust test suite.
- [x] 8.4 Run Dart formatting, Flutter analysis, focused snapshot/controller/top-bar/task-panel widget tests, and the complete Flutter test suite.
- [x] 8.5 Regenerate bindings in the supported build environment and run the production Linux build/package checks needed to catch bridge or native dependency integration failures.
- [x] 8.6 Validate manually against a test Vikunja account for discovery, allowed projects, date/priority mapping, background refresh, restart cache, custom CA if available, completion, un-completion, recurring-task reconciliation, and concurrent-edit conflict behavior.
- [x] 8.7 Run `openspec validate add-caldav-task-panel --strict` and review the final diff against proposal non-goals, existing Google Calendar behavior, rebuild isolation, and generated-file policy.
