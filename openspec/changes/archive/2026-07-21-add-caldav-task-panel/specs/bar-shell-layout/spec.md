## MODIFIED Requirements

### Requirement: Right group modules
The right group SHALL render system, task, tray, notification, and power modules in the implemented order.

#### Scenario: Right group is rendered
- **WHEN** the bar builds from a snapshot and config
- **THEN** Alice SHALL render the implemented right-group modules in a right-aligned wrapping group
- **AND** the exact module order SHALL depend on whether valid CalDAV configuration is present as specified below

#### Scenario: Right group is rendered without CalDAV
- **WHEN** the bar builds from a snapshot and config without valid CalDAV configuration
- **THEN** Alice SHALL render memory, CPU, network, clock, enabled weather, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group

#### Scenario: Right group is rendered with CalDAV
- **WHEN** the bar builds from a snapshot and valid CalDAV configuration
- **THEN** Alice SHALL render memory, CPU, network, tasks, clock, enabled weather, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group
- **AND** the task module SHALL appear immediately before the clock module
