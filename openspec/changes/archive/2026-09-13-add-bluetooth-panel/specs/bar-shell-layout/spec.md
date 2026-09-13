## MODIFIED Requirements

### Requirement: Right group modules
The right group SHALL render system, task, tray, notification, and power modules in the implemented order.

#### Scenario: Right group is rendered
- **WHEN** the bar builds from a snapshot and config
- **THEN** Alice SHALL render the implemented right-group modules in a right-aligned wrapping group
- **AND** the exact module order SHALL depend on Bluetooth availability and whether valid CalDAV configuration is present as specified below

#### Scenario: Right group is rendered without CalDAV
- **WHEN** the bar builds from a snapshot and config without valid CalDAV configuration and Bluetooth is unavailable
- **THEN** Alice SHALL render memory, CPU, network, clock, enabled weather, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group

#### Scenario: Right group is rendered without CalDAV and with Bluetooth
- **WHEN** the bar builds from a snapshot and config without valid CalDAV configuration and Bluetooth is available
- **THEN** Alice SHALL render memory, CPU, Bluetooth, network, clock, enabled weather, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group

#### Scenario: Right group is rendered with CalDAV
- **WHEN** the bar builds from a snapshot and valid CalDAV configuration and Bluetooth is available
- **THEN** Alice SHALL render memory, CPU, Bluetooth, network, tasks, clock, enabled weather, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group
- **AND** the task module SHALL appear immediately before the clock module

## ADDED Requirements

### Requirement: Conditional interactive Bluetooth control
The right group SHALL render an icon-only Bluetooth control immediately before the network control only while Bluetooth is available. Activating it SHALL toggle the Bluetooth panel.

#### Scenario: Bluetooth is available
- **WHEN** BlueZ is available and at least one Bluetooth adapter is powered
- **THEN** Alice SHALL render the Bluetooth control without a text label immediately before the network control
- **AND** activating it SHALL toggle the Bluetooth panel

#### Scenario: Bluetooth is unavailable
- **WHEN** BlueZ is unavailable or no Bluetooth adapter is powered
- **THEN** Alice SHALL NOT render the Bluetooth control

#### Scenario: Bluetooth panel is open
- **WHEN** the Bluetooth panel is open for a bar
- **THEN** Alice SHALL render the corresponding Bluetooth control in its open-panel visual state
