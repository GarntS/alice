# Snapshot Runtime Specification

## Purpose
Define the Rust-to-Flutter state stream that drives the bar and panels.

## Requirements

### Requirement: Snapshot data contract
Alice SHALL expose a `BarSnapshot` containing workspaces, optional media, memory usage, CPU usage, network status, clock status, tray items, and notifications.

#### Scenario: Snapshot is sent
- **WHEN** the runtime builds a snapshot
- **THEN** the snapshot SHALL contain all implemented state fields required by the Flutter bar and panels

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
- **THEN** Alice SHALL emit triggers from a 1 second stats timer, a 30 second clock timer, Sway workspace events, `/sys/class/net` notifications, StatusNotifier watcher events, and freedesktop notification events
- **AND** Alice SHALL emit an initial trigger immediately

### Requirement: Debounced emission
Alice SHALL debounce bursts of runtime triggers before sending snapshots to Flutter.

#### Scenario: Multiple triggers occur quickly
- **WHEN** one or more triggers are received
- **THEN** Alice SHALL wait approximately 50 ms
- **AND** Alice SHALL drain any pending trigger burst before building and sending one snapshot

### Requirement: Provider failure tolerance
Alice SHALL tolerate individual provider failures by using implemented fallback values.

#### Scenario: A provider read fails
- **WHEN** a workspace, media, network, clock, tray, stats, or notification provider cannot produce data
- **THEN** Alice SHALL continue constructing a snapshot using empty, null, zero, or disconnected fallback values as implemented
