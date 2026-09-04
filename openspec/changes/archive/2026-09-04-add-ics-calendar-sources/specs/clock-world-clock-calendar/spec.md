## MODIFIED Requirements

### Requirement: Calendar configuration gating
Alice SHALL hide the calendar events section when no enabled calendar entries are configured.

#### Scenario: Calendar config is absent
- **WHEN** Flutter requests events and Rust has no enabled calendar entries
- **THEN** Rust SHALL return status `not_configured`
- **AND** the panel SHALL render no events/auth section

### Requirement: Calendar event fetching and caching
Alice SHALL fetch and cache events from every enabled calendar source for a multi-month window and return merged events for the selected date. Google source updates and ICS source updates SHALL use one shared mapping policy for source-scoped event identity, title fallback, date, all-day state, local-time labels, calendar name, and calendar color.

#### Scenario: Configured source events are available
- **WHEN** a date is requested after one or more calendar sources have supplied events
- **THEN** Alice SHALL return all matching events from those sources
- **AND** Alice SHALL map events through the shared event-mapping policy

#### Scenario: Authorized fetch occurs
- **WHEN** authorization is available and a date is requested
- **THEN** Alice SHALL fetch or read cached Google source events for a window spanning approximately three months before through three months after the selected date
- **AND** Alice SHALL map fetched events through the shared event-mapping policy
- **AND** Alice SHALL return status `ready` with events matching the requested date

#### Scenario: Incremental event update occurs
- **WHEN** Google incremental synchronization returns a non-cancelled event with a usable start date
- **THEN** Alice SHALL replace its prior source-scoped cache entry by id
- **AND** Alice SHALL map the updated event through the same event-mapping policy used by full fetches
- **AND** Alice SHALL preserve source-scoped incremental sync-token and sorting behavior

#### Scenario: Incremental event is cancelled
- **WHEN** Google incremental synchronization returns a cancelled event
- **THEN** Alice SHALL remove the existing source-scoped cache entry for that event
- **AND** Alice SHALL NOT reinsert it through the shared mapper

#### Scenario: Cached date is requested
- **WHEN** a requested date falls inside the cached event window
- **THEN** Alice SHALL return matching cached events without a source refetch caused by that request

#### Scenario: Google calendar color is available
- **WHEN** a Google event's remote calendar provides a color and its configured entry has no color
- **THEN** Alice SHALL use the remote calendar color

#### Scenario: Google calendar color fallback is required
- **WHEN** a Google event's remote calendar provides no color and its configured entry has a valid color
- **THEN** Alice SHALL use the configured entry color
