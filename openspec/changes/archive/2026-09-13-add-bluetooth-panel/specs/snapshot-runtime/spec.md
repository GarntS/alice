## MODIFIED Requirements

### Requirement: Snapshot data contract
Alice SHALL expose a `BarSnapshot` containing workspaces, optional media, memory usage, CPU usage, Bluetooth status, network status, clock status, optional weather, tray items, notifications, and CalDAV task synchronization state with normalized tasks.

#### Scenario: Snapshot is sent
- **WHEN** the runtime builds a snapshot
- **THEN** the snapshot SHALL contain all implemented state fields required by the Flutter bar and panels
- **AND** the snapshot SHALL include cached Bluetooth availability and device-management state
- **AND** the snapshot SHALL include optional weather data when a successful weather response is cached
- **AND** the snapshot SHALL include normalized CalDAV task data, freshness, last-success information, and redacted error state when CalDAV is configured
- **AND** the snapshot SHALL NOT include the configured CalDAV token or cached VEVENT records

### Requirement: Trigger sources
Alice SHALL rebuild snapshots from implemented timer and event sources.

#### Scenario: Runtime starts
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL emit triggers from a 1 second stats timer, a 30 second clock timer, Bluetooth service or device-state changes, CalDAV cache changes when configured, weather refresh events when weather is enabled and valid, Sway workspace events, `/sys/class/net` notifications, StatusNotifier watcher events, freedesktop notification events, MPRIS player lifecycle events, and MPRIS player property-change events
- **AND** Alice SHALL emit media-position refresh triggers while the selected MPRIS player is playing
- **AND** Alice SHALL emit an initial trigger immediately

### Requirement: Provider failure tolerance
Alice SHALL tolerate individual provider failures by using implemented fallback values.

#### Scenario: A provider read fails
- **WHEN** a workspace, media, Bluetooth, network, clock, weather, tray, stats, notification, or CalDAV task provider cannot produce data
- **THEN** Alice SHALL continue constructing a snapshot using empty, null, zero, disconnected, stale, or error fallback values as implemented
- **AND** a CalDAV provider failure SHALL NOT discard previously cached task data

### Requirement: Testable snapshot aggregation
Alice SHALL expose snapshot aggregation logic through a testable boundary that can be exercised with fake providers while preserving the production snapshot stream behavior.

#### Scenario: Fake providers produce a complete snapshot
- **WHEN** tests assemble a snapshot from fake workspace, media, stats, Bluetooth, network, clock, weather, tray, notification, and CalDAV task inputs
- **THEN** Alice SHALL produce a `BarSnapshot` containing those provided values
- **AND** the test SHALL NOT require live Sway IPC, MPRIS, D-Bus, procfs, Bluetooth adapters, network interfaces, Pirate Weather HTTP requests, StatusNotifier items, or a CalDAV server

#### Scenario: Fake providers fail independently
- **WHEN** one or more fake providers return errors during test snapshot assembly
- **THEN** Alice SHALL still produce a `BarSnapshot`
- **AND** failed providers SHALL contribute the same fallback values used by the production snapshot builder

## ADDED Requirements

### Requirement: Cached Bluetooth runtime integration
Alice SHALL perform Bluetooth and BlueZ operations outside snapshot assembly and SHALL read Bluetooth state from a runtime-owned cache during snapshot assembly.

#### Scenario: Snapshot assembly uses Bluetooth cache
- **WHEN** the runtime builds a snapshot for any trigger
- **THEN** Alice SHALL read Bluetooth availability and device-management state from the runtime-owned Bluetooth cache
- **AND** Alice SHALL NOT perform BlueZ discovery, device reads, pairing, connecting, disconnecting, or D-Bus service discovery solely because snapshot assembly occurred

#### Scenario: Bluetooth cache changes
- **WHEN** Bluetooth availability, observed devices, scan state, operation state, pairing prompt, authorization prompt, or Bluetooth error state changes
- **THEN** Alice SHALL emit a runtime trigger
- **AND** the next debounced snapshot SHALL contain the changed Bluetooth state
