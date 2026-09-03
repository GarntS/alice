## MODIFIED Requirements

### Requirement: Bar window configuration
Alice SHALL configure each main bar window as a top layer-shell surface on its associated monitor when layer-shell is supported.

#### Scenario: Layer-shell bar is created
- **WHEN** Alice starts on a supported compositor with one or more monitors
- **THEN** it SHALL create one bar surface for each startup monitor
- **AND** each bar SHALL be anchored to that monitor's top, left, and right edges
- **AND** each bar SHALL use the top-layer namespace and reserve an exclusive zone for its 44 px height

### Requirement: Panel window configuration
Alice SHALL create floating panel windows lazily and position them relative to the bar that captured the panel anchor.

#### Scenario: Panel is shown
- **WHEN** Flutter sends `showPanel` with a panel id, source bar identity, output-local anchor, alignment, size, and gap
- **THEN** the C++ runner SHALL create or reuse a panel `FlView`
- **AND** it SHALL attach the panel to the source bar's monitor
- **AND** it SHALL calculate the panel's horizontal placement from the output-local anchor
- **AND** it SHALL notify Dart of the secondary view id after the native window is shown

#### Scenario: Panel is shown from a monitor with a non-zero desktop origin
- **WHEN** a user opens a panel from a bar whose monitor has a non-zero virtual-desktop X or Y origin
- **THEN** the panel SHALL remain positioned relative to the source bar's monitor
- **AND** its placement SHALL not depend on that monitor's virtual-desktop origin

### Requirement: Dismiss overlay
Alice SHALL provide a native click target that dismisses the current panel when the user clicks outside the panel on its source monitor.

#### Scenario: A panel is shown from a bar
- **WHEN** Alice displays a panel invoked from a bar
- **THEN** it SHALL attach the dismiss overlay to the same monitor as that panel

#### Scenario: Dismiss overlay is clicked
- **WHEN** the dismiss overlay receives a button press
- **THEN** Alice SHALL hide the current panel and dismiss overlay
- **AND** Alice SHALL notify Dart that the panel has hidden
