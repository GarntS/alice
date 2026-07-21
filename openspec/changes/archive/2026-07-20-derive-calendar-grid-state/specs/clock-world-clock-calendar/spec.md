## MODIFIED Requirements

### Requirement: Calendar date picker
Alice SHALL include a Sunday-first month-view calendar in the clock panel with six rows of seven consecutive dates and selected-day, current-day, and event-indicator states. The current-day state SHALL be derived from the current local date when the calendar renders.

#### Scenario: Date is selected
- **WHEN** the user selects a day in the calendar
- **THEN** Alice SHALL update the selected date
- **AND** Alice SHALL fetch Google Calendar events for that date

#### Scenario: Month changes
- **WHEN** the displayed month changes
- **THEN** Alice SHALL render the six-week grid for that month
- **AND** Alice SHALL refresh event indicators for days in that month
- **AND** Alice SHALL invoke the month-change callback once for that navigation action

#### Scenario: Month begins after Sunday
- **WHEN** the first day of the displayed month is not Sunday
- **THEN** the first grid row SHALL begin with dates from the preceding month on the prior Sunday
- **AND** the grid SHALL contain exactly 42 consecutive dates

#### Scenario: Current local date changes
- **WHEN** the calendar renders after the current local date has changed
- **THEN** Alice SHALL derive the today highlight from the new current local date
- **AND** Alice SHALL NOT rely on a today value retained from widget initialization
