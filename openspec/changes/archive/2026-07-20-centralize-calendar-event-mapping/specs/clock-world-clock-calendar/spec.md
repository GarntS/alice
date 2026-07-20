## MODIFIED Requirements

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
