## MODIFIED Requirements

### Requirement: Weather bar widget
Alice SHALL render an enabled weather bar widget to the right of the clock.

#### Scenario: Weather data is available
- **WHEN** weather is enabled and a weather snapshot is available
- **THEN** the top bar SHALL render a weather widget immediately to the right of the clock
- **AND** the widget SHALL show a Phosphor icon representing current weather
- **AND** the widget SHALL show the current temperature value followed by a degree symbol
- **AND** the widget tooltip SHALL contain `Last Updated <timestamp>` using the cached last-updated timestamp

#### Scenario: Weather is enabled with no data
- **WHEN** weather is enabled and no weather snapshot is available
- **THEN** the top bar SHALL render a weather widget immediately to the right of the clock
- **AND** the widget SHALL show a cloud icon and `-`

#### Scenario: Weather widget is clicked
- **WHEN** the user clicks the weather widget
- **THEN** Alice SHALL toggle the weather panel

### Requirement: Weather icon presentation
Alice SHALL map Pirate Weather icon strings and weather metrics to Phosphor icons.

#### Scenario: Current or forecast weather icon is rendered
- **WHEN** Alice renders weather with a Pirate Weather icon string
- **THEN** `clear-day` SHALL render as a sun icon
- **AND** `clear-night` SHALL render as a moon icon
- **AND** `rain` SHALL render as a rain icon
- **AND** `snow` SHALL render as a snow icon
- **AND** `sleet` SHALL render as a sleet or icy precipitation icon
- **AND** `wind` SHALL render as a wind icon
- **AND** `fog` SHALL render as a fog icon
- **AND** `cloudy` SHALL render as a cloud icon
- **AND** `partly-cloudy-day` SHALL render as a sun/cloud icon
- **AND** `partly-cloudy-night` SHALL render as a moon/cloud icon

#### Scenario: Moon phase is available
- **WHEN** Alice renders a daily card with moon phase data
- **THEN** Alice SHALL vary the night/moon icon according to the moon phase value

#### Scenario: Wind direction icon is rendered
- **WHEN** Alice renders a wind direction icon with a wind bearing
- **THEN** Alice SHALL round the bearing to the nearest 45 degrees
- **AND** Alice SHALL use a corresponding pre-rotated Phosphor direction icon such as west or north-west
- **AND** the icon SHALL indicate the direction the wind is blowing toward
