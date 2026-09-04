## Purpose

Define timely, deduplicated Alice notifications for ICS VALARMs and configured default reminders without requiring clock-panel interaction.

## ADDED Requirements

### Requirement: ICS VALARM notifications
Alice SHALL create one Alice notification for each due ICS VALARM trigger associated with a timed event, including absolute and event-relative triggers.

#### Scenario: A VALARM trigger becomes due
- **WHEN** an ICS VALARM trigger becomes due for a parsed timed event
- **THEN** Alice SHALL create a notification identifying the calendar event

#### Scenario: Repeating VALARM is parsed
- **WHEN** a VALARM specifies REPEAT and DURATION
- **THEN** Alice SHALL emit only the initial alarm notification

### Requirement: Default ICS event reminders
Alice SHALL create reminders 30 minutes, 10 minutes, and 2 minutes before every timed ICS event when its entry enables `notify_for_events`.

#### Scenario: Event reminders are enabled
- **WHEN** an upcoming timed ICS event belongs to an entry with `notify_for_events` enabled or omitted
- **THEN** Alice SHALL create one notification at each of 30, 10, and 2 minutes before the event

#### Scenario: Event reminders are disabled
- **WHEN** an ICS entry sets `notify_for_events` to false
- **THEN** Alice SHALL NOT create default event-reminder notifications for that entry

#### Scenario: All-day event is scheduled
- **WHEN** an ICS event is all-day
- **THEN** Alice SHALL NOT create default event-reminder notifications for it

### Requirement: Reminder de-duplication and late triggers
Alice SHALL notify at most once for each alarm or default reminder identity and SHALL not replay reminders whose scheduled time has already passed when source data is refreshed or Alice starts.

#### Scenario: Source data is refreshed repeatedly
- **WHEN** the same event occurrence and reminder are encountered in multiple refreshes
- **THEN** Alice SHALL create no more than one notification for that reminder

#### Scenario: Reminder is discovered after it is due
- **WHEN** source data is first parsed after an alarm or default reminder's scheduled time
- **THEN** Alice SHALL NOT create that stale notification
