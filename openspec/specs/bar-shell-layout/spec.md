# Bar Shell Layout Specification

## Purpose
Define the visible top bar structure and the composition of implemented bar modules.
## Requirements
### Requirement: Top bar surface layout
Alice SHALL render a top-aligned 44 px bar divided into left, center, and right layout groups.

#### Scenario: Bar is rendered with default surface styling
- **WHEN** the Flutter bar view builds with transparent top bar disabled
- **THEN** Alice SHALL render a 44 px high container with horizontal padding and themed surface styling
- **AND** Alice SHALL arrange content into three expanded horizontal groups

#### Scenario: Bar is rendered with transparent surface styling
- **WHEN** the Flutter bar view builds with transparent top bar enabled
- **THEN** Alice SHALL render a 44 px high container with horizontal padding and no outer background fill
- **AND** Alice SHALL render no outer accent-colored border around the top bar shell
- **AND** Alice SHALL arrange content into three expanded horizontal groups
- **AND** Alice SHALL preserve child module styling, including pills, workspace chips, highlights, and child borders

### Requirement: Left group workspaces
The left group SHALL render Sway workspace chips from the current snapshot.

#### Scenario: Workspace snapshots are available
- **WHEN** the snapshot contains workspaces
- **THEN** Alice SHALL render one chip per workspace in a wrapping row
- **AND** focused, visible-unfocused, and hidden workspaces SHALL use distinct visual treatments

### Requirement: Center group media
The center group SHALL render now-playing media only when an MPRIS media snapshot exists.

#### Scenario: No media snapshot exists
- **WHEN** `snapshot.media` is null
- **THEN** Alice SHALL render no center media pill

#### Scenario: Media snapshot exists
- **WHEN** `snapshot.media` contains a current track
- **THEN** Alice SHALL render a centered media pill showing playback state, title, artist, position, and length

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

### Requirement: Bar widgets are snapshot-driven
Bar widgets SHALL render from `BarSnapshot` plus configuration and SHALL delegate actions through callbacks rather than reading system state directly.

#### Scenario: Snapshot update arrives
- **WHEN** a new `BarSnapshot` is received over the platform stream
- **THEN** Alice SHALL update the displayed bar modules from the new snapshot values

### Requirement: Interactive icon-only network control
The right-group network module SHALL be an icon-only control that opens the Network panel and SHALL retain its position in the implemented module order.

#### Scenario: Network module is rendered
- **WHEN** the right group is rendered
- **THEN** Alice SHALL render the network module without a text label
- **AND** activating it SHALL toggle the Network panel

#### Scenario: Battery data is unavailable
- **WHEN** battery display is enabled but no battery data is available
- **THEN** Alice SHALL omit the battery slot and its extra spacing
- **AND** the gap between the CPU and network controls SHALL remain the normal module gap

#### Scenario: Network panel is open
- **WHEN** the Network panel is open for a bar
- **THEN** Alice SHALL render the corresponding network control in its open-panel visual state

