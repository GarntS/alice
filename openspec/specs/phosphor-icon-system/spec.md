# phosphor-icon-system Specification

## Purpose
Define a consistent, configurable Phosphor icon presentation for Alice-owned interface symbols while preserving semantic and externally supplied artwork.
## Requirements
### Requirement: Phosphor interface icon presentation
Alice SHALL render every Alice-owned interface symbol that was represented by a Material icon using a corresponding Phosphor icon.

#### Scenario: Alice-owned icon is rendered
- **WHEN** Alice renders an icon for a bar module, panel control, panel status, weather condition, weather metric, or fallback state
- **THEN** it SHALL render a Phosphor icon with equivalent meaning
- **AND** it SHALL NOT render a Material icon glyph

#### Scenario: External artwork is rendered
- **WHEN** a tray item or notification provides application-supplied icon artwork
- **THEN** Alice SHALL render the supplied artwork unchanged
- **AND** it SHALL use a Phosphor icon only when it needs an Alice-owned fallback icon

### Requirement: Configurable Phosphor icon style
Alice SHALL render Alice-owned Phosphor icons in duotone or regular style according to the configured icon-style preference.

#### Scenario: Duotone icons are enabled
- **WHEN** `theme.use_duotone_icons` is `true`
- **THEN** Alice SHALL render Alice-owned Phosphor icons in duotone style

#### Scenario: Regular icons are enabled
- **WHEN** `theme.use_duotone_icons` is `false`
- **THEN** Alice SHALL render Alice-owned Phosphor icons in regular style

### Requirement: Duotone icon colors
Alice SHALL preserve an icon's contextual primary color and apply the configured secondary-color policy to duotone icons.

#### Scenario: Accent secondary color is enabled
- **WHEN** `theme.use_duotone_icons` and `theme.use_accent_on_icons` are both `true`
- **THEN** a duotone icon's secondary layer SHALL use Alice's configured accent color
- **AND** its primary layer SHALL retain its contextual color

#### Scenario: Gray secondary color is enabled
- **WHEN** `theme.use_duotone_icons` is `true` and `theme.use_accent_on_icons` is `false`
- **THEN** a duotone icon's secondary layer SHALL use Alice's fixed theme-aware gray color
- **AND** its primary layer SHALL retain its contextual color

#### Scenario: Contextual icon color is semantic
- **WHEN** an icon is rendered in a warning, alert, highlighted, or contrasting context
- **THEN** its primary layer SHALL retain that context's existing semantic or contrasting color

### Requirement: Semantic battery icon descriptors
Alice SHALL provide semantic Alice-owned Phosphor descriptors for horizontal full, high, medium, low, warning, and charging battery states in both regular and duotone styles.

#### Scenario: Battery module selects an icon state
- **WHEN** the battery module needs a capacity-level or charging icon
- **THEN** it SHALL use the corresponding semantic battery descriptor
- **AND** the descriptor SHALL support both configured Phosphor presentation styles

