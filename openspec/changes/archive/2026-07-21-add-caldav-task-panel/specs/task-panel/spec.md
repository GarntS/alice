## ADDED Requirements

### Requirement: Compact task bar module
Alice SHALL render a task panel module immediately before the clock when valid CalDAV configuration is present. The module SHALL expose current incomplete due-today and overdue counts and SHALL toggle the task panel.

#### Scenario: Today and overdue tasks exist
- **WHEN** the CalDAV task state is current and either count is non-zero
- **THEN** Alice SHALL show a compact task icon with each non-zero count
- **AND** Alice SHALL visually distinguish the overdue count from the today count

#### Scenario: No task is due or overdue
- **WHEN** both the today and overdue counts are zero
- **THEN** Alice SHALL render only the task icon
- **AND** the icon SHALL remain interactive so the panel can open

#### Scenario: Task synchronization has failed
- **WHEN** task synchronization state is an error
- **THEN** Alice SHALL replace due counts with a compact error indication
- **AND** activating the module SHALL still open the panel

#### Scenario: CalDAV is disabled
- **WHEN** valid CalDAV configuration is absent
- **THEN** Alice SHALL render no task bar module

### Requirement: Date-grouped active task presentation
Alice SHALL present every active allowed task in ascending due-date blocks, followed by an undated block, with named and colored priority cues and collection source information.

#### Scenario: Overdue, today, and future tasks exist
- **WHEN** the task panel renders active dated tasks
- **THEN** Alice SHALL render overdue date blocks above today's block
- **AND** Alice SHALL render future date blocks after today's block in ascending date order
- **AND** each date block SHALL sort tasks by Do Now, Urgent, High, Medium, Low, case-insensitive title, and stable resource href

#### Scenario: Task has no due date
- **WHEN** an active task has no normalized due date
- **THEN** Alice SHALL render it in a `No due date` block after all active dated blocks
- **AND** the undated block SHALL sort by priority, title, and resource href

#### Scenario: Task row is rendered
- **WHEN** Alice renders an active task
- **THEN** the row SHALL show its light-outline checkbox, medium-weight title, named colored priority text, and smaller muted collection display name
- **AND** Alice SHALL distinguish title and metadata through typography, color, and spacing without an inner card background or border
- **AND** Do Now and Urgent SHALL use red, High SHALL use orange, Medium SHALL use green, and Low or unprioritized SHALL use blue
- **AND** priority SHALL NOT be conveyed by color alone

#### Scenario: Due header is rendered
- **WHEN** Alice renders a date block in the current year
- **THEN** Alice SHALL use a human date with no time and omit the year
- **AND** today's header SHALL use the form `Today - <day> <full month>`
- **AND** `Today -`, day numbers, and years SHALL use bold black text
- **AND** full month names SHALL use bold accent-colored text
- **AND** date headers SHALL use slightly larger type with compact spacing and include no calendar icon, card background, or border
- **AND** the date label and right-justified task count SHALL be vertically centered on the same line

#### Scenario: Due date is outside the current year
- **WHEN** Alice renders a date block whose date is outside the current year
- **THEN** Alice SHALL include its year
- **AND** Alice SHALL display no due time

### Requirement: Completed-today presentation
Alice SHALL render tasks completed on the current local date as grayed-out rows in a terminal `Completed today` section and SHALL omit tasks completed on earlier dates.

#### Scenario: Tasks were completed today
- **WHEN** one or more allowed tasks have a local completion date equal to today
- **THEN** Alice SHALL render them after dated and undated active tasks
- **AND** Alice SHALL sort them by completion instant descending, then priority, title, and resource href
- **AND** Alice SHALL NOT display their completion times

#### Scenario: Task was completed before today
- **WHEN** a task's local completion date is before today
- **THEN** Alice SHALL not render it in the task panel

#### Scenario: Completed row is rendered
- **WHEN** Alice renders a completed-today task
- **THEN** Alice SHALL gray out the row
- **AND** Alice SHALL keep its completion checkbox interactive
- **AND** the checkbox SHALL be the only row target that un-completes the task

### Requirement: Optimistic completion interaction
Alice SHALL move a checkbox-toggled task optimistically to its requested section, prevent duplicate mutation requests while pending, and reconcile the row with the server result.

#### Scenario: Active checkbox is selected
- **WHEN** the user checks an active task
- **THEN** Alice SHALL move it immediately to the `Completed today` section
- **AND** Alice SHALL mark its checkbox mutation pending
- **AND** Alice SHALL request completion through the native CalDAV action

#### Scenario: Completed checkbox is cleared
- **WHEN** the user unchecks a completed-today task
- **THEN** Alice SHALL move it immediately to its due-date or undated active block
- **AND** Alice SHALL mark its checkbox mutation pending
- **AND** Alice SHALL request un-completion through the native CalDAV action

#### Scenario: Pending mutation succeeds
- **WHEN** the server confirms the requested completion state
- **THEN** Alice SHALL clear the pending indication
- **AND** Alice SHALL reconcile the row from the authoritative snapshot

#### Scenario: Pending mutation fails
- **WHEN** the native CalDAV action returns an error
- **THEN** Alice SHALL remove the optimistic override
- **AND** Alice SHALL restore the row to its prior snapshot-backed section
- **AND** Alice SHALL display a non-secret action error

#### Scenario: Non-checkbox task area is activated
- **WHEN** the user activates a task title, project label, date area, or row whitespace
- **THEN** Alice SHALL NOT create, edit, delete, navigate to, complete, or un-complete the task

### Requirement: Task panel synchronization states
Alice SHALL make task loading, stale cache, errors, manual refresh, and empty results explicit while keeping cached rows usable for inspection.

#### Scenario: Panel opens
- **WHEN** the task panel opens
- **THEN** Alice SHALL request an immediate CalDAV refresh
- **AND** Alice SHALL keep rendering any available cached tasks while that refresh is pending

#### Scenario: User requests manual refresh
- **WHEN** the user activates the panel refresh control
- **THEN** Alice SHALL request synchronization
- **AND** Alice SHALL prevent overlapping refresh actions from starting duplicate synchronization passes

#### Scenario: Cached data is stale or synchronization failed
- **WHEN** cached tasks are available but the latest synchronization is stale or failed
- **THEN** Alice SHALL display the cached grouped list
- **AND** Alice SHALL display a stale or error banner with a redacted message
- **AND** Alice SHALL place last-success information in a visually separated footer below the task content

#### Scenario: No tasks exist after successful synchronization
- **WHEN** synchronization is current and no active or completed-today tasks are visible
- **THEN** Alice SHALL display a task-list empty state

#### Scenario: Initial synchronization has no cache
- **WHEN** no cached tasks exist and initial synchronization is still pending
- **THEN** Alice SHALL display a loading state

### Requirement: Task panel visual hierarchy
Alice SHALL use the configured accent color for the task panel heading, summary typography, and non-error date labels, and SHALL separate summary, sections, rows, state messages, and synchronization metadata through type weight, type size, semantic color, and spacing. Inner task-panel elements SHALL NOT use card backgrounds or borders.

#### Scenario: Task summary is rendered
- **WHEN** Alice renders active, today, and overdue counts
- **THEN** Alice SHALL place all three metrics on one compact horizontal row
- **AND** each metric SHALL use a semantic colored icon and number followed by a black non-number label

#### Scenario: Task panel has short content
- **WHEN** the visible task sections require less than the task panel maximum height
- **THEN** the panel card SHALL size to its content like the calendar panel
- **AND** the list SHALL remain scrollable when content exceeds the maximum height

### Requirement: Date-relative task state rollover
Alice SHALL recompute overdue, today, and completed-today membership when the machine-local calendar date changes without requiring a task resource change.

#### Scenario: Local midnight passes
- **WHEN** Alice's local date advances while the task data is otherwise unchanged
- **THEN** yesterday's incomplete due tasks SHALL become overdue
- **AND** the new day's incomplete due tasks SHALL become due today
- **AND** tasks completed on the prior day SHALL leave the completed-today section
- **AND** affected bar counts and panel sections SHALL update
