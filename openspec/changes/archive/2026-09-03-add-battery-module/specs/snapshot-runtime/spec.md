## ADDED Requirements

### Requirement: Battery snapshot state
Alice SHALL include optional battery state in `BarSnapshot`, including the selected battery's integer capacity and status needed for presentation.

#### Scenario: Usable battery data is available
- **WHEN** snapshot assembly reads valid data for an enabled battery
- **THEN** the emitted `BarSnapshot` SHALL contain the battery capacity and status

#### Scenario: Battery data is unavailable
- **WHEN** battery discovery or reading does not yield valid battery data
- **THEN** the emitted `BarSnapshot` SHALL contain no battery state

### Requirement: Battery polling
Alice SHALL refresh battery state on the snapshot runtime's one-second metric polling trigger.

#### Scenario: Metric polling timer ticks
- **WHEN** the one-second metric timer triggers a snapshot rebuild
- **THEN** Alice SHALL re-read the enabled battery state before emitting the snapshot

### Requirement: Testable battery snapshot aggregation
Alice SHALL allow tests to inject battery-provider results into snapshot assembly without requiring live sysfs power-supply files.

#### Scenario: Fake battery provider succeeds or fails
- **WHEN** a snapshot aggregation test supplies valid battery data or a battery-provider failure
- **THEN** the resulting snapshot SHALL respectively contain battery state or no battery state
- **AND** the test SHALL not require `/sys/class/power_supply`
