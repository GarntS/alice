## ADDED Requirements

### Requirement: Testable snapshot aggregation
Alice SHALL expose snapshot aggregation logic through a testable boundary that can be exercised with fake providers while preserving the production snapshot stream behavior.

#### Scenario: Fake providers produce a complete snapshot
- **WHEN** tests assemble a snapshot from fake workspace, media, stats, network, clock, tray, and notification inputs
- **THEN** Alice SHALL produce a `BarSnapshot` containing those provided values
- **AND** the test SHALL NOT require live Sway IPC, MPRIS, D-Bus, procfs, network interfaces, or StatusNotifier items

#### Scenario: Fake providers fail independently
- **WHEN** one or more fake providers return errors during test snapshot assembly
- **THEN** Alice SHALL still produce a `BarSnapshot`
- **AND** failed providers SHALL contribute the same fallback values used by the production snapshot builder
