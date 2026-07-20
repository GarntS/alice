# Clock, World Clock, and Calendar Specification

## Purpose
Define the implemented clock snapshot, world-clock panel, date picker, and Google Calendar event integration.

## Requirements

### Requirement: Local clock snapshot
Alice SHALL expose local time as a clock snapshot containing time zone code, date label, and 24-hour time label.

#### Scenario: Clock provider reads local time
- **WHEN** Alice builds a clock snapshot
- **THEN** it SHALL format the date as `dd MMM`
- **AND** it SHALL format the time as `HH:MM`
- **AND** it SHALL derive a short time zone code from local time, system time zone information, or known offset mapping where possible

### Requirement: Clock bar and world clock panel
Alice SHALL render the local clock on the bar and configured additional time zones in the clock panel.

#### Scenario: Clock module is rendered
- **WHEN** the bar renders the clock module
- **THEN** it SHALL show the configured local time zone label when present, otherwise the snapshot time zone code
- **AND** it SHALL show the current date and time labels

#### Scenario: Clock panel is opened
- **WHEN** the clock panel is rendered
- **THEN** Alice SHALL show a highlighted local time row
- **AND** Alice SHALL show one row per configured additional time zone using its label and fixed offset from UTC

### Requirement: Calendar date picker
Alice SHALL include a month-view calendar in the clock panel with selected-day, today, and event-indicator states.

#### Scenario: Date is selected
- **WHEN** the user selects a day in the calendar
- **THEN** Alice SHALL update the selected date
- **AND** Alice SHALL fetch Google Calendar events for that date

#### Scenario: Month changes
- **WHEN** the displayed month changes
- **THEN** Alice SHALL refresh event indicators for days in that month

### Requirement: Calendar configuration gating
Alice SHALL hide the calendar events section when Google Calendar credentials are not configured.

#### Scenario: Calendar config is absent
- **WHEN** Flutter requests events and Rust has no calendar config
- **THEN** Rust SHALL return status `not_configured`
- **AND** the panel SHALL render no events/auth section

### Requirement: Google Calendar authorization and token storage
Alice SHALL support Google Calendar authorization using configured Google OAuth client id and secret, persist tokens under Alice's config directory, and expose authorization progress through fetch statuses.

#### Scenario: No token exists
- **WHEN** events are fetched for the first time with calendar config present and no cached token
- **THEN** Alice SHALL start an authorization flow in a background thread
- **AND** Alice SHALL return `needs_auth` with an authorization URL when available

#### Scenario: Authorization is pending
- **WHEN** authorization has started but has not completed
- **THEN** Alice SHALL return `polling` with the pending authorization URL
- **AND** the Flutter panel SHALL poll periodically until the result changes

### Requirement: Calendar event fetching and caching
Alice SHALL fetch read-only Google Calendar events for a multi-month window, cache them, and return events for the selected date. Initial full-fetch events and incremental-sync events SHALL use one shared mapping policy for event id, title fallback, date, all-day state, local-time labels, calendar name, and calendar color.

#### Scenario: Authorized fetch occurs
- **WHEN** authorization is available and a date is requested
- **THEN** Alice SHALL fetch calendar metadata and events for a window spanning approximately three months before through three months after the selected date
- **AND** Alice SHALL map fetched events through the shared event-mapping policy
- **AND** Alice SHALL return status `ready` with events matching the requested date

#### Scenario: Incremental event update occurs
- **WHEN** incremental synchronization returns a non-cancelled event with a usable start date
- **THEN** Alice SHALL replace its prior cache entry by id
- **AND** Alice SHALL map the updated event through the same event-mapping policy used by full fetches
- **AND** Alice SHALL preserve incremental sync-token and sorting behavior

#### Scenario: Incremental event is cancelled
- **WHEN** incremental synchronization returns a cancelled event
- **THEN** Alice SHALL remove the existing cache entry for that event id
- **AND** Alice SHALL NOT reinsert it through the shared mapper

#### Scenario: Cached date is requested
- **WHEN** a requested date falls inside the cached event window
- **THEN** Alice SHALL return matching cached events without a full refetch

### Requirement: Calendar event presentation
Alice SHALL render all-day and timed calendar events with calendar colors when available.

#### Scenario: Events are ready
- **WHEN** the events result has status `ready`
- **THEN** Alice SHALL render all-day events before timed events
- **AND** timed events SHALL display local start and end labels
- **AND** event color dots SHALL use the calendar color when provided
