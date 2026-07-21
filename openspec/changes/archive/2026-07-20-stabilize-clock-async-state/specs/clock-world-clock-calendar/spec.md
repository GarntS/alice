## ADDED Requirements

### Requirement: Active calendar request ownership
Alice SHALL apply asynchronous calendar event results only when they belong to the latest event request for the currently selected date.

#### Scenario: Older selected-date request finishes last
- **WHEN** the user selects a second date before the first date's event request completes and the first request finishes after the second
- **THEN** Alice SHALL continue displaying the second date's event result
- **AND** the older result SHALL NOT replace the active loading, result, polling, or indicator state

#### Scenario: Latest selected-date request completes
- **WHEN** the latest request for the currently selected date completes while the clock panel is mounted
- **THEN** Alice SHALL display that result
- **AND** Alice SHALL update loading and authorization-polling state from that result

### Requirement: Current-date authorization polling
While calendar authorization is pending, Alice SHALL poll for the date that is selected at the time of each poll tick.

#### Scenario: Date changes during authorization polling
- **WHEN** authorization polling starts for one date and the user selects another date before a subsequent poll tick
- **THEN** the subsequent poll SHALL request the newly selected date
- **AND** Alice SHALL retain the existing five-second polling cadence

#### Scenario: Polling status ends
- **WHEN** the accepted active result is neither `needs_auth` nor `polling`
- **THEN** Alice SHALL stop the authorization polling timer

### Requirement: Active month-indicator request ownership
Alice SHALL apply asynchronous calendar indicators only when they belong to the latest indicator request for the currently displayed month.

#### Scenario: Older month request finishes last
- **WHEN** the displayed month changes before its prior indicator request completes and the prior request finishes after the current month's request
- **THEN** Alice SHALL retain indicators for the currently displayed month
- **AND** the older month SHALL NOT replace them

#### Scenario: Clock panel is disposed with work pending
- **WHEN** the clock panel is disposed while event, indicator, or polling work is pending
- **THEN** Alice SHALL cancel its polling timer
- **AND** later asynchronous completions SHALL NOT mutate disposed widget state
