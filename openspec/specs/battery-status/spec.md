# battery-status Specification

## Purpose
Provide a compact, reliable battery-capacity and charging-state indicator for supported Linux devices without showing a meaningless module on systems without a usable battery.
## Requirements
### Requirement: Battery discovery and device selection
Alice SHALL obtain battery data from `/sys/class/power_supply`. When no device is configured, Alice SHALL select a power-supply entry whose `type` value is `Battery`. When a device name is configured, Alice SHALL use that entry instead of auto-discovery.

#### Scenario: Battery is auto-detected
- **WHEN** battery display is enabled, no device name is configured, and a power-supply entry reports `type` as `Battery`
- **THEN** Alice SHALL use that entry as the battery source

#### Scenario: Configured device takes precedence
- **WHEN** battery display is enabled and `battery.device_name` identifies a power-supply entry
- **THEN** Alice SHALL read battery state from that entry
- **AND** Alice SHALL NOT replace it with an auto-detected entry

### Requirement: Battery data availability
Alice SHALL expose no battery state when the module is disabled, no usable battery can be selected, or the selected device's capacity or status cannot be read as required.

#### Scenario: System has no battery
- **WHEN** no configured device is available and no power-supply entry reports `type` as `Battery`
- **THEN** Alice SHALL expose no battery state
- **AND** the bar SHALL not render a battery module

#### Scenario: Battery data cannot be read
- **WHEN** the selected device's `capacity` or `status` file is absent, unreadable, or invalid
- **THEN** Alice SHALL expose no battery state
- **AND** the bar SHALL not render a battery module

### Requirement: Battery capacity and charging presentation
Alice SHALL show the selected device's integer capacity as `<capacity>%` beside a horizontal battery icon. `Charging` and `Full` status values SHALL use the charging icon regardless of capacity. Other statuses SHALL select icons by capacity: 0–10 warning, 11–33 low, 34–55 medium, 56–77 high, and 78–100 full.

#### Scenario: Battery is charging
- **WHEN** the selected battery reports a status of `Charging` or `Full`
- **THEN** the bar SHALL show the charging battery icon and the capacity percentage

#### Scenario: Battery is discharging at a level boundary
- **WHEN** the selected battery has a non-charging status and reports capacity 10, 33, 55, 77, or 78
- **THEN** the bar SHALL respectively show warning, low, medium, high, or full battery iconography
- **AND** the bar SHALL show the capacity with a `%` suffix

### Requirement: Battery icon style consistency
Alice SHALL render battery icons as Alice-owned horizontal Phosphor icons using the configured regular or duotone icon style.

#### Scenario: Icon style is changed
- **WHEN** the configured Phosphor icon presentation is regular or duotone
- **THEN** the battery module SHALL use the corresponding style for its selected icon

