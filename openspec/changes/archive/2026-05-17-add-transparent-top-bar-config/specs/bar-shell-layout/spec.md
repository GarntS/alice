## MODIFIED Requirements

### Requirement: Top bar surface layout
Alice SHALL render a top-aligned 44 px bar divided into left, center, and right layout groups.

#### Scenario: Bar is rendered with default surface styling
- **WHEN** the Flutter bar view builds with transparent top bar disabled
- **THEN** Alice SHALL render a 44 px high container with horizontal padding and themed surface styling
- **AND** Alice SHALL arrange content into three expanded horizontal groups

#### Scenario: Bar is rendered with transparent surface styling
- **WHEN** the Flutter bar view builds with transparent top bar enabled
- **THEN** Alice SHALL render a 44 px high container with horizontal padding and no outer background fill
- **AND** Alice SHALL render no outer accent-colored border around the top bar shell
- **AND** Alice SHALL arrange content into three expanded horizontal groups
- **AND** Alice SHALL preserve child module styling, including pills, workspace chips, highlights, and child borders
