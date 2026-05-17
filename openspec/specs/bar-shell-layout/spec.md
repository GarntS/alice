# Bar Shell Layout Specification

## Purpose
Define the visible top bar structure and the composition of implemented bar modules.

## Requirements

### Requirement: Top bar surface layout
Alice SHALL render a top-aligned 44 px bar divided into left, center, and right layout groups.

#### Scenario: Bar is rendered
- **WHEN** the Flutter bar view builds
- **THEN** Alice SHALL render a 44 px high container with horizontal padding and themed surface styling
- **AND** Alice SHALL arrange content into three expanded horizontal groups

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
The right group SHALL render system, tray, notification, and power modules in the implemented order.

#### Scenario: Right group is rendered
- **WHEN** the bar builds from a snapshot and config
- **THEN** Alice SHALL render memory, CPU, network, clock, visible tray items, tray overflow when needed, notifications, and power in a right-aligned wrapping group

### Requirement: Bar widgets are snapshot-driven
Bar widgets SHALL render from `BarSnapshot` plus configuration and SHALL delegate actions through callbacks rather than reading system state directly.

#### Scenario: Snapshot update arrives
- **WHEN** a new `BarSnapshot` is received over the platform stream
- **THEN** Alice SHALL update the displayed bar modules from the new snapshot values
