## ADDED Requirements

### Requirement: Semantic battery icon descriptors
Alice SHALL provide semantic Alice-owned Phosphor descriptors for horizontal full, high, medium, low, warning, and charging battery states in both regular and duotone styles.

#### Scenario: Battery module selects an icon state
- **WHEN** the battery module needs a capacity-level or charging icon
- **THEN** it SHALL use the corresponding semantic battery descriptor
- **AND** the descriptor SHALL support both configured Phosphor presentation styles
