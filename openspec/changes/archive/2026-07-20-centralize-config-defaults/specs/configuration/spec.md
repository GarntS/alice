## MODIFIED Requirements

### Requirement: Defaults and invalid-value fallback
Alice SHALL define omitted optional configuration values from the typed `AliceConfig` defaults rather than repeating scalar fallback literals in raw-to-typed conversion. The shipped default template and `AliceConfig::default()` SHALL produce equivalent effective typed configuration. The second built-in world-clock default SHALL follow the template's `Australia/Sydney` IANA time zone, including its current daylight-saving abbreviation and UTC offset.

#### Scenario: Missing optional sections
- **WHEN** the YAML omits optional `theme`, `network`, `tray`, `clock`, `power`, `calendar`, `notifications`, or `weather` fields
- **THEN** Alice SHALL use built-in typed defaults for omitted fields
- **AND** raw-to-typed conversion SHALL preserve implemented normalization and minimum-value rules

#### Scenario: Shipped template is parsed
- **WHEN** Alice parses `DEFAULT_CONFIG_TEMPLATE`
- **THEN** its effective typed configuration SHALL equal `AliceConfig::default()`
- **AND** this parity SHALL be verified by a deterministic automated contract test

#### Scenario: Sydney is in standard or daylight time
- **WHEN** `AliceConfig::default()` constructs its second world-clock entry
- **THEN** Alice SHALL resolve `Australia/Sydney` using `chrono-tz`
- **AND** the label and offset SHALL reflect the current AEST or AEDT period

#### Scenario: Invalid accent color or empty commands
- **WHEN** `theme.accent` is not a `#RRGGBB` hex color
- **THEN** Alice SHALL use the default accent color `#4C956C`
- **WHEN** a power command is empty or whitespace
- **THEN** Alice SHALL use that action's typed default command
