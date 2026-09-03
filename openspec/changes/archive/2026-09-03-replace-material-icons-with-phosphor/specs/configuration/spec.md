## ADDED Requirements

### Requirement: Icon presentation configuration
Alice SHALL support optional `theme.use_duotone_icons` and `theme.use_accent_on_icons` boolean configuration fields in its typed Rust and Flutter configuration models.

#### Scenario: Icon presentation preferences are omitted
- **WHEN** the YAML omits `theme.use_duotone_icons` or `theme.use_accent_on_icons`
- **THEN** Alice SHALL default each omitted preference to `true`

#### Scenario: Icon presentation preferences are provided
- **WHEN** the YAML provides `theme.use_duotone_icons` or `theme.use_accent_on_icons`
- **THEN** Alice SHALL expose the provided boolean value in the typed configuration model returned to Flutter

#### Scenario: Shipped icon presentation defaults are parsed
- **WHEN** Alice parses the shipped default configuration template
- **THEN** its effective icon presentation preferences SHALL equal the typed configuration defaults
