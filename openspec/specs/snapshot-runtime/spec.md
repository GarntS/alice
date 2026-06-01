# Snapshot Runtime Specification

## Purpose
Define the Rust-to-Flutter state stream that drives the bar and panels.
## Requirements
### Requirement: Snapshot data contract
Alice SHALL expose a `BarSnapshot` containing workspaces, optional media, memory usage, CPU usage, network status, clock status, optional weather, tray items, and notifications.

#### Scenario: Snapshot is sent
- **WHEN** the runtime builds a snapshot
- **THEN** the snapshot SHALL contain all implemented state fields required by the Flutter bar and panels
- **AND** the snapshot SHALL include optional weather data when a successful weather response is cached

### Requirement: Snapshot stream startup
Alice SHALL expose `watchBarSnapshots` over flutter_rust_bridge and start a Rust runtime-backed producer for snapshots.

#### Scenario: Flutter subscribes
- **WHEN** Flutter calls `watchBarSnapshots`
- **THEN** Rust SHALL spawn the snapshot stream thread
- **AND** Rust SHALL create a Tokio runtime for periodic and event-driven triggers

### Requirement: Trigger sources
Alice SHALL rebuild snapshots from implemented timer and event sources.

#### Scenario: Runtime starts
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL emit triggers from a 1 second stats timer, a 30 second clock timer, weather refresh events when weather is enabled and valid, Sway workspace events, `/sys/class/net` notifications, StatusNotifier watcher events, freedesktop notification events, MPRIS player lifecycle events, and MPRIS player property-change events
- **AND** Alice SHALL emit media-position refresh triggers while the selected MPRIS player is playing
- **AND** Alice SHALL emit an initial trigger immediately

### Requirement: Cached provider state in snapshot runtime
Alice SHALL allow runtime-owned providers to maintain state that can be read during snapshot assembly without external I/O.

#### Scenario: Snapshot assembly uses runtime-owned media cache
- **WHEN** the snapshot runtime builds a snapshot
- **THEN** Alice SHALL read media state from the runtime-owned MPRIS cache provider
- **AND** Alice SHALL avoid performing MPRIS D-Bus discovery or property reads solely because an unrelated snapshot trigger fired

#### Scenario: Snapshot assembly uses runtime-owned weather cache
- **WHEN** the snapshot runtime builds a snapshot
- **THEN** Alice SHALL read weather state from the runtime-owned weather cache provider
- **AND** Alice SHALL avoid performing Pirate Weather HTTP requests solely because an unrelated snapshot trigger fired

### Requirement: Media-position trigger independence
Alice SHALL keep media elapsed-position repainting independent from system metric polling.

#### Scenario: Metrics polling cadence changes
- **WHEN** a selected MPRIS player is playing
- **THEN** Alice SHALL continue emitting snapshot triggers for media position refreshes even if system metric polling is slowed, disabled, or otherwise not responsible for the refresh

### Requirement: Debounced emission
Alice SHALL debounce bursts of runtime triggers before sending snapshots to Flutter.

#### Scenario: Multiple triggers occur quickly
- **WHEN** one or more triggers are received
- **THEN** Alice SHALL wait approximately 50 ms
- **AND** Alice SHALL drain any pending trigger burst before building and sending one snapshot

### Requirement: Provider failure tolerance
Alice SHALL tolerate individual provider failures by using implemented fallback values.

#### Scenario: A provider read fails
- **WHEN** a workspace, media, network, clock, weather, tray, stats, or notification provider cannot produce data
- **THEN** Alice SHALL continue constructing a snapshot using empty, null, zero, or disconnected fallback values as implemented

### Requirement: Testable snapshot aggregation
Alice SHALL expose snapshot aggregation logic through a testable boundary that can be exercised with fake providers while preserving the production snapshot stream behavior.

#### Scenario: Fake providers produce a complete snapshot
- **WHEN** tests assemble a snapshot from fake workspace, media, stats, network, clock, weather, tray, and notification inputs
- **THEN** Alice SHALL produce a `BarSnapshot` containing those provided values
- **AND** the test SHALL NOT require live Sway IPC, MPRIS, D-Bus, procfs, network interfaces, Pirate Weather HTTP requests, or StatusNotifier items

#### Scenario: Fake providers fail independently
- **WHEN** one or more fake providers return errors during test snapshot assembly
- **THEN** Alice SHALL still produce a `BarSnapshot`
- **AND** failed providers SHALL contribute the same fallback values used by the production snapshot builder

### Requirement: Weather refresh runtime
Alice SHALL run a weather refresh task when weather is enabled and valid.

#### Scenario: Weather runtime starts
- **WHEN** the snapshot runtime starts with enabled and valid weather configuration
- **THEN** Alice SHALL request weather immediately
- **AND** Alice SHALL update the runtime-owned weather cache on success
- **AND** Alice SHALL emit a snapshot trigger when cached weather data changes

#### Scenario: Weather refresh interval elapses
- **WHEN** the effective refresh interval plus jitter elapses
- **THEN** Alice SHALL request a fresh Pirate Weather response
- **AND** Alice SHALL replace the cached weather response on success
- **AND** Alice SHALL wait for the next interval after failure rather than retrying immediately

#### Scenario: Weather is disabled or invalid
- **WHEN** the snapshot runtime starts with disabled weather or invalid weather configuration
- **THEN** Alice SHALL NOT start Pirate Weather request polling
- **AND** Alice SHALL expose no weather data in snapshots

