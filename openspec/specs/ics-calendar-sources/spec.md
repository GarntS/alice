# ics-calendar-sources Specification

## Purpose
Define local-file and HTTP(S) iCalendar calendar sources that remain current independently and contribute normalized events to Alice's calendar.
## Requirements
### Requirement: ICS calendar source acquisition
Alice SHALL support `ics` calendar entries backed by exactly one local `path` or HTTP(S) `url`, and SHALL refresh each entry independently at its effective polling interval.

#### Scenario: Local file source is configured
- **WHEN** an ICS entry configures a readable local path
- **THEN** Alice SHALL read and parse that file at startup and at the entry's polling interval

#### Scenario: Remote source is configured
- **WHEN** an ICS entry configures an HTTPS or HTTP URL
- **THEN** Alice SHALL request and parse that URL at startup and at the entry's polling interval

#### Scenario: Source refresh fails after a successful fetch
- **WHEN** a previously parsed ICS source cannot be read, fetched, or parsed on refresh
- **THEN** Alice SHALL retain its last successfully parsed events
- **AND** Alice SHALL report the failure without terminating the calendar runtime

### Requirement: ICS event normalization and recurrence
Alice SHALL expose valid ICS VEVENT occurrences as calendar events using local date and time labels, including all-day events and recurring occurrences in the active event window.

#### Scenario: Recurring event is in the event window
- **WHEN** an ICS VEVENT recurrence produces an occurrence in the active event window
- **THEN** Alice SHALL expose that occurrence on its local calendar date
- **AND** Alice SHALL honor RRULE, RDATE, EXDATE, and detached recurrence exceptions

#### Scenario: ICS event has a configured color
- **WHEN** an ICS entry has a valid configured hex color
- **THEN** Alice SHALL use that color for every event from the entry

#### Scenario: ICS event has no configured color
- **WHEN** an ICS entry omits a color
- **THEN** Alice SHALL use the fixed ICS default red color for its events

### Requirement: Calendar source runtime lifecycle
Alice SHALL start configured calendar source refresh and event scheduling during application startup without requiring the clock panel to be opened.

#### Scenario: Clock panel remains closed
- **WHEN** Alice starts with an enabled ICS source and the user never opens the clock panel
- **THEN** Alice SHALL continue refreshing the source and maintain its upcoming events for notification scheduling

