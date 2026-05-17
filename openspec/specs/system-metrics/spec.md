# System Metrics Specification

## Purpose
Define implemented memory and CPU collection and top-bar metric presentation.

## Requirements

### Requirement: Memory usage from procfs
Alice SHALL calculate memory usage percentage from `/proc/meminfo`.

#### Scenario: Meminfo is readable
- **WHEN** `MemTotal` and `MemAvailable` are present
- **THEN** Alice SHALL calculate memory usage as `(MemTotal - MemAvailable) / MemTotal * 100`
- **AND** Alice SHALL expose the value as `memory_usage_percent` in `BarSnapshot`

### Requirement: CPU usage from procfs
Alice SHALL calculate aggregate active CPU cores from per-core lines in `/proc/stat`.

#### Scenario: Stat file is readable
- **WHEN** Alice reads per-core `cpuN` lines
- **THEN** Alice SHALL compute each core's active fraction from cumulative user, nice, system, irq, softirq, steal, idle, and iowait fields
- **AND** Alice SHALL sum the active fractions into `cpu_usage_cores`

### Requirement: Metric polling
Alice SHALL refresh system metrics on the snapshot runtime's 1 second trigger.

#### Scenario: Stats timer ticks
- **WHEN** the 1 second timer triggers a snapshot rebuild
- **THEN** Alice SHALL re-read memory and CPU values through the procfs stats provider

### Requirement: Metric presentation
Alice SHALL render memory as a rounded percentage and CPU as a one-decimal aggregate core value.

#### Scenario: Metrics are displayed
- **WHEN** the bar renders metric modules
- **THEN** memory SHALL display as `<percent>%` with zero decimals
- **AND** CPU SHALL display as a one-decimal numeric label
- **AND** the metric pills SHALL use the implemented warning and alert thresholds
