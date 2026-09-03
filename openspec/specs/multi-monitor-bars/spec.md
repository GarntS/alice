# multi-monitor-bars Specification

## Purpose
Provide a consistent Alice bar on every monitor available at startup, with interactions retaining the monitor from which they originated.
## Requirements
### Requirement: A bar is rendered on every startup monitor
When layer-shell support is available, Alice SHALL render one top bar on every monitor available when the application starts.

#### Scenario: Multiple monitors are available at startup
- **WHEN** Alice starts with two or more active monitors
- **THEN** it renders one 44 px top bar on each monitor

#### Scenario: Bar content is shared across startup monitors
- **WHEN** Alice renders bars on multiple monitors
- **THEN** each bar presents the same shared Alice bar data and controls

### Requirement: Panel invocation retains its source bar
Alice SHALL associate a panel invocation with the bar on which its control was clicked.

#### Scenario: A panel control is clicked on a non-primary monitor
- **WHEN** a user clicks a panel-opening control on a bar attached to a non-primary monitor
- **THEN** Alice records that bar as the panel invocation source

### Requirement: Open-state feedback is source-specific
Alice SHALL show an open-panel visual state only on the control in the bar that invoked the currently open panel.

#### Scenario: A panel opens from one of several bars
- **WHEN** a user opens a panel from one bar while multiple bars are visible
- **THEN** Alice highlights the invoking control only on that bar
- **AND** it does not highlight matching controls on other bars

