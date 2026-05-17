## MODIFIED Requirements

### Requirement: Trigger sources
Alice SHALL rebuild snapshots from implemented timer and event sources.

#### Scenario: Runtime starts
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL emit triggers from a 1 second stats timer, a 30 second clock timer, Sway workspace events, `/sys/class/net` notifications, StatusNotifier watcher events, freedesktop notification events, MPRIS player lifecycle events, and MPRIS player property-change events
- **AND** Alice SHALL emit media-position refresh triggers while the selected MPRIS player is playing
- **AND** Alice SHALL emit an initial trigger immediately

## ADDED Requirements

### Requirement: Cached provider state in snapshot runtime
Alice SHALL allow runtime-owned providers to maintain state that can be read during snapshot assembly without external I/O.

#### Scenario: Snapshot assembly uses runtime-owned media cache
- **WHEN** the snapshot runtime builds a snapshot
- **THEN** Alice SHALL read media state from the runtime-owned MPRIS cache provider
- **AND** Alice SHALL avoid performing MPRIS D-Bus discovery or property reads solely because an unrelated snapshot trigger fired

### Requirement: Media-position trigger independence
Alice SHALL keep media elapsed-position repainting independent from system metric polling.

#### Scenario: Metrics polling cadence changes
- **WHEN** a selected MPRIS player is playing
- **THEN** Alice SHALL continue emitting snapshot triggers for media position refreshes even if system metric polling is slowed, disabled, or otherwise not responsible for the refresh
