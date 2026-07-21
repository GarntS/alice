## ADDED Requirements

### Requirement: CalDAV account activation and secure transport
Alice SHALL start the CalDAV integration only from a valid configured account, authenticate with the configured username and token, require HTTPS unless cleartext HTTP is explicitly enabled, verify HTTPS with system roots plus an optional configured custom CA, and prevent credentials from crossing origins or appearing in logs and UI state.

#### Scenario: CalDAV is not configured
- **WHEN** the configuration omits the `caldav` section
- **THEN** Alice SHALL NOT start CalDAV discovery or synchronization
- **AND** Alice SHALL NOT expose an enabled task module

#### Scenario: Cleartext HTTP is not enabled
- **WHEN** `caldav.allow_http` is false or omitted
- **THEN** Alice SHALL reject an `http://` principal URL before synchronization starts

#### Scenario: Cleartext HTTP is explicitly enabled
- **WHEN** `caldav.allow_http` is true and the principal uses `http://`
- **THEN** Alice SHALL permit authenticated HTTP requests to that exact origin
- **AND** Alice SHALL reject redirects or hrefs that change scheme, host, or effective port

#### Scenario: Custom CA is configured
- **WHEN** a valid `caldav.ca_certificate_path` is configured
- **THEN** Alice SHALL add that certificate to the system trust roots used for CalDAV requests
- **AND** Alice SHALL continue to verify the server certificate and hostname

#### Scenario: Redirect or collection href changes origin
- **WHEN** a CalDAV response would send an authenticated request to an origin different from the configured principal origin
- **THEN** Alice SHALL reject the request
- **AND** Alice SHALL NOT forward the configured credential

#### Scenario: CalDAV operation fails
- **WHEN** Alice logs or exposes a CalDAV configuration, protocol, or transport error
- **THEN** Alice SHALL redact the configured token and authorization header
- **AND** Alice SHALL NOT include raw resource bodies in the error

### Requirement: Allowed collection discovery
Alice SHALL discover CalDAV collection metadata and component capabilities from the configured principal while synchronizing only canonical collection hrefs present in the configured allowlist.

#### Scenario: Allowed collections are discovered
- **WHEN** discovery returns readable collections whose canonical hrefs are allowlisted
- **THEN** Alice SHALL retain their hrefs, display names, and supported component types
- **AND** Alice SHALL synchronize VTODO or VEVENT according to each collection's capabilities

#### Scenario: Vikunja projects are discovered
- **WHEN** the principal advertises `/dav/projects/` as its calendar home
- **THEN** Alice SHALL enumerate individual `/dav/projects/<project-id>` collections from that home
- **AND** Alice SHALL treat configured and advertised collection hrefs that differ only by a trailing slash as the same allowlist entry
- **AND** Alice SHALL fetch and update task resources using the hrefs returned for the allowlisted project

#### Scenario: Calendar home is configured as a collection
- **WHEN** the allowlist contains the discovered calendar-home href rather than an individual task collection
- **THEN** Alice SHALL expose a clear configuration error
- **AND** Alice SHALL NOT implicitly synchronize every discovered project

#### Scenario: Discovered collection is not allowed
- **WHEN** discovery returns a collection whose canonical href is not in the allowlist
- **THEN** Alice SHALL NOT fetch or cache resources from that collection

#### Scenario: Configured collection is unavailable
- **WHEN** an allowlisted collection cannot be discovered or read
- **THEN** Alice SHALL expose a redacted synchronization error for that collection
- **AND** Alice SHALL continue synchronizing other readable allowed collections

### Requirement: Incremental CalDAV synchronization
Alice SHALL synchronize allowed collections at startup, at the configured interval, when the task panel requests refresh, and when a manual refresh is requested. Alice SHALL prefer RFC 6578 incremental synchronization and SHALL use bounded full synchronization when incremental synchronization is unavailable or invalid.

#### Scenario: Initial synchronization runs
- **WHEN** the CalDAV runtime starts with valid configuration
- **THEN** Alice SHALL request an immediate synchronization
- **AND** Alice SHALL populate allowed VTODO resources and bounded VEVENT resources
- **AND** Alice SHALL persist collection ETags and sync tokens returned by the server

#### Scenario: Poll interval elapses
- **WHEN** the effective CalDAV polling interval elapses
- **THEN** Alice SHALL request changes for allowed collections
- **AND** Alice SHALL coalesce the request with any synchronization already in flight

#### Scenario: Sync token is accepted
- **WHEN** a collection supports incremental synchronization and its persisted token is valid
- **THEN** Alice SHALL apply changed and deleted resource responses
- **AND** Alice SHALL persist the replacement sync token

#### Scenario: Sync token is invalid
- **WHEN** a server reports that a collection's sync token is invalid
- **THEN** Alice SHALL clear only that collection's token
- **AND** Alice SHALL perform a bounded full synchronization for that collection

#### Scenario: Collection does not support incremental synchronization
- **WHEN** an allowed collection does not support RFC 6578 incremental synchronization
- **THEN** Alice SHALL use CalDAV query and multiget behavior or an equivalent bounded full synchronization
- **AND** Alice SHALL reconcile changed and removed resources by href and ETag

### Requirement: Persistent CalDAV cache and freshness
Alice SHALL atomically persist versioned CalDAV collection state and lossless resource data under Alice's XDG cache directory with owner-only permissions, and SHALL expose cached data independently from current synchronization freshness.

#### Scenario: Valid cache exists at startup
- **WHEN** Alice starts with a valid persisted CalDAV cache
- **THEN** Alice SHALL publish its cached task data before the first live synchronization completes
- **AND** Alice SHALL mark that data stale until a live synchronization succeeds

#### Scenario: Cache is written
- **WHEN** synchronization or a confirmed mutation changes cached state
- **THEN** Alice SHALL write the replacement cache atomically
- **AND** the cache file SHALL be restricted to mode `0600`

#### Scenario: Persisted cache is invalid or incompatible
- **WHEN** the cache cannot be parsed or has an unsupported version
- **THEN** Alice SHALL ignore or quarantine it
- **AND** Alice SHALL perform a full synchronization without failing application startup

#### Scenario: Synchronization fails with cached data
- **WHEN** a live synchronization fails after cached task data has been loaded
- **THEN** Alice SHALL retain the cached data
- **AND** Alice SHALL expose an error state, stale state, and last successful synchronization time

### Requirement: VTODO normalization
Alice SHALL normalize each visible VTODO into a stable resource identity, title, collection name, local due date, local completion instant, task state, and five-level priority while preserving its lossless iCalendar resource for writes.

#### Scenario: Date-only due value is parsed
- **WHEN** a VTODO has a `DUE;VALUE=DATE` value
- **THEN** Alice SHALL preserve that calendar date without timezone conversion
- **AND** Alice SHALL expose no due time to Flutter

#### Scenario: Date-time due value is parsed
- **WHEN** a VTODO has a UTC, TZID, or floating DATE-TIME `DUE` value
- **THEN** Alice SHALL interpret it according to its iCalendar timezone semantics
- **AND** Alice SHALL convert it to Alice's machine-local calendar date
- **AND** Alice SHALL expose no due time to Flutter

#### Scenario: Priority is normalized
- **WHEN** a VTODO priority is `1`, `2`, `3..4`, `5`, or `0`, absent, or `6..9`
- **THEN** Alice SHALL map it respectively to Do Now, Urgent, High, Medium, or Low

#### Scenario: Task status is normalized
- **WHEN** a VTODO status is `NEEDS-ACTION`, `IN-PROCESS`, absent, `COMPLETED`, or `CANCELLED`
- **THEN** Alice SHALL respectively treat it as active, active, active, completed, or hidden

#### Scenario: Completed instant is parsed
- **WHEN** a completed VTODO contains `COMPLETED`
- **THEN** Alice SHALL retain its instant for local completion-day filtering and ordering
- **AND** Alice SHALL NOT expose a completion time label to the UI

### Requirement: VEVENT synchronization and recurrence preservation
Alice SHALL parse and cache VEVENT resources intersecting a rolling window approximately three months before through three months after the current local date, including recurrence and timezone metadata, without expanding recurring occurrences or exposing event UI.

#### Scenario: Event falls inside the event window
- **WHEN** an allowed event-capable collection returns a VEVENT intersecting the rolling window
- **THEN** Alice SHALL cache its normalized base fields and lossless resource data
- **AND** Alice SHALL retain RRULE, RDATE, EXDATE, RECURRENCE-ID, and referenced VTIMEZONE information when present

#### Scenario: Recurring event is cached
- **WHEN** a VEVENT defines recurrence
- **THEN** Alice SHALL preserve the recurrence definition and detached exceptions
- **AND** Alice SHALL NOT materialize occurrences in this change

#### Scenario: Event falls outside the shifted window
- **WHEN** the local date changes enough that a cached event no longer intersects the rolling event window
- **THEN** Alice SHALL evict the out-of-window event during window reconciliation

#### Scenario: Task snapshot is emitted
- **WHEN** the Rust runtime publishes CalDAV-backed UI state
- **THEN** Alice SHALL include normalized task data and synchronization state
- **AND** Alice SHALL NOT expose cached VEVENT records through the Flutter UI contract in this change

### Requirement: Conflict-safe completion mutation
Alice SHALL complete and un-complete existing tasks by patching the latest lossless VTODO resource, preserving unrelated data, and guarding writes with the current ETag.

#### Scenario: Task is completed successfully
- **WHEN** the user requests completion of an active task
- **THEN** Alice SHALL set `STATUS:COMPLETED`
- **AND** Alice SHALL set `COMPLETED` to the current UTC instant
- **AND** Alice SHALL set `PERCENT-COMPLETE:100`
- **AND** Alice SHALL PUT the resource with `If-Match` using its current ETag

#### Scenario: Task is un-completed successfully
- **WHEN** the user requests un-completion of a completed task
- **THEN** Alice SHALL set `STATUS:NEEDS-ACTION`
- **AND** Alice SHALL remove `COMPLETED`
- **AND** Alice SHALL set `PERCENT-COMPLETE:0`
- **AND** Alice SHALL PUT the resource with `If-Match` using its current ETag

#### Scenario: Completion patch is built
- **WHEN** Alice changes completion properties
- **THEN** Alice SHALL preserve UID, summary, descriptions, dates, recurrence, alarms, categories, relationships, unknown properties, timezone components, and unrelated sibling components

#### Scenario: ETag precondition fails once
- **WHEN** the first PUT returns a precondition failure
- **THEN** Alice SHALL refetch the latest resource
- **AND** Alice SHALL reapply the requested completion state
- **AND** Alice SHALL retry once with the latest ETag

#### Scenario: Completion write fails
- **WHEN** the write or its single conflict retry fails
- **THEN** Alice SHALL leave the authoritative cache unchanged
- **AND** Alice SHALL return a redacted action error so Flutter can revert its optimistic state

#### Scenario: Completion write succeeds
- **WHEN** the server accepts the mutation
- **THEN** Alice SHALL reconcile the cache from the authoritative returned or refetched resource
- **AND** Alice SHALL persist the updated resource and emit a snapshot trigger
