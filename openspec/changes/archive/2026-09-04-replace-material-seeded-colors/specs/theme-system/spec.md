## MODIFIED Requirements

### Requirement: Accent-derived Material theme
Alice SHALL build explicit light and dark Material color schemes from Alice-owned color tokens instead of a Material 3 seeded palette. Each scheme SHALL retain Flutter Material theme compatibility while mapping the configured exact accent to `primary`, the subtle accent token to `primaryContainer`, and the neutral raised-container token to `secondaryContainer`.

#### Scenario: Theme is built
- **WHEN** Alice builds a light or dark theme
- **THEN** it SHALL NOT derive the color scheme with `ColorScheme.fromSeed`
- **AND** it SHALL use Alice-defined neutral surface, foreground, and secondary colors
- **AND** it SHALL expose an explicit Material color scheme and transparent scaffold colors

#### Scenario: Material component consumes theme roles
- **WHEN** an Alice or stock Material component reads a mapped primary, container, surface, outline, error, or warning theme role
- **THEN** it SHALL receive the corresponding explicit Alice color token
