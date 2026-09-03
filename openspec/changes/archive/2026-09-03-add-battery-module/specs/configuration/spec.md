## ADDED Requirements

### Requirement: Battery configuration
Alice SHALL support a top-level `battery` configuration section with optional `enable` and `device_name` fields. Omitted `enable` SHALL default to `true`; omitted or blank `device_name` SHALL select automatic battery discovery. Alice SHALL expose the effective battery configuration in the typed Flutter UI configuration model.

#### Scenario: Battery settings are omitted
- **WHEN** the YAML omits the `battery` section or its fields
- **THEN** Alice SHALL enable battery display by default
- **AND** Alice SHALL use automatic battery discovery

#### Scenario: Battery settings are provided
- **WHEN** the YAML provides `battery.enable` or a non-blank `battery.device_name`
- **THEN** Alice SHALL use the supplied enablement value and device name
- **AND** Alice SHALL expose the effective values to Flutter

#### Scenario: Battery is disabled
- **WHEN** `battery.enable` is `false`
- **THEN** Alice SHALL not display the battery module
