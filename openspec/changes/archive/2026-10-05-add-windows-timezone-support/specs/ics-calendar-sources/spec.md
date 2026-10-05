## ADDED Requirements

### Requirement: Windows timezone identifiers in ICS sources
Alice SHALL resolve recognized Windows timezone identifiers in ICS date-time properties to date-aware timezone rules using the worldwide default mapping when no territory is supplied. Recognized Windows identifiers SHALL take precedence over the existing embedded fixed-offset fallback. Resolution SHALL apply consistently to event starts and ends, RDATE, EXDATE, RECURRENCE-ID, detached exception times, and timezone-qualified absolute alarm triggers.

#### Scenario: Eastern daylight-time event with embedded standard offset
- **WHEN** an ICS event starts at `20261005T123000` with `TZID=Eastern Standard Time` and its embedded VTIMEZONE lists standard offset `-0500` first
- **THEN** Alice SHALL normalize its start to `2026-10-05T16:30:00Z`
- **AND** a display in America/New_York SHALL show `12:30`, not `13:30`

#### Scenario: Eastern standard-time event
- **WHEN** an ICS event starts at `20261207T123000` with `TZID=Eastern Standard Time`
- **THEN** Alice SHALL normalize its start to `2026-12-07T17:30:00Z`

#### Scenario: Windows zone without an embedded definition
- **WHEN** an event uses a recognized Windows timezone identifier without a corresponding VTIMEZONE
- **THEN** Alice SHALL resolve it using that timezone's date-specific rules rather than the host timezone

#### Scenario: Recurrence crosses a daylight-saving boundary
- **WHEN** a recurring event at 12:30 in Eastern Standard Time has occurrences on October 26 and November 2, 2026
- **THEN** its normalized starts SHALL be 16:30 UTC and 17:30 UTC respectively
- **AND** its event-zone wall time SHALL remain 12:30

#### Scenario: Generated recurrence end times
- **WHEN** a timed recurring event supplies DTSTART and DTEND
- **THEN** each generated occurrence SHALL preserve the elapsed duration of the master event rather than reuse its absolute end date
- **AND** detached exceptions SHALL use their own start and end times

#### Scenario: Exclusions and detached exceptions use Windows zones
- **WHEN** a series, RDATE, EXDATE, RECURRENCE-ID, and detached exception dates use recognized Windows timezone identifiers
- **THEN** Alice SHALL apply their date-specific offsets consistently
- **AND** exclusions SHALL remove the matching occurrence and detached exceptions SHALL replace, not duplicate, the matching occurrence

#### Scenario: Alarm timing follows the resolved event zone
- **WHEN** an event has a relative reminder or a timezone-qualified absolute alarm in a recognized Windows timezone
- **THEN** Alice SHALL schedule that reminder using the correctly normalized UTC instant

### Requirement: Existing ICS timezone compatibility
Alice SHALL preserve existing UTC, IANA timezone, floating date-time, all-day, and unrecognized timezone fallback behavior while adding Windows identifier support.

#### Scenario: Existing supported time representations
- **WHEN** an ICS source contains UTC date-times, recognized IANA TZIDs, floating date-times, or date-only all-day events
- **THEN** Alice SHALL retain their existing normalization semantics

#### Scenario: Unrecognized identifier has an embedded offset
- **WHEN** a TZID is neither a recognized IANA nor a recognized Windows identifier and its VTIMEZONE supplies an offset
- **THEN** Alice SHALL retain the existing embedded fixed-offset fallback

#### Scenario: Unrecognized identifier has no embedded offset
- **WHEN** a TZID is unrecognized and has no usable embedded offset
- **THEN** Alice SHALL retain the existing host-local fallback
