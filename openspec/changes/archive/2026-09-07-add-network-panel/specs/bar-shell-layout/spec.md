## ADDED Requirements

### Requirement: Interactive icon-only network control
The right-group network module SHALL be an icon-only control that opens the Network panel and SHALL retain its position in the implemented module order.

#### Scenario: Network module is rendered
- **WHEN** the right group is rendered
- **THEN** Alice SHALL render the network module without a text label
- **AND** activating it SHALL toggle the Network panel

#### Scenario: Battery data is unavailable
- **WHEN** battery display is enabled but no battery data is available
- **THEN** Alice SHALL omit the battery slot and its extra spacing
- **AND** the gap between the CPU and network controls SHALL remain the normal module gap

#### Scenario: Network panel is open
- **WHEN** the Network panel is open for a bar
- **THEN** Alice SHALL render the corresponding network control in its open-panel visual state
