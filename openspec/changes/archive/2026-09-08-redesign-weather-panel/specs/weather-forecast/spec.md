## MODIFIED Requirements

### Requirement: Weather panel current conditions
Alice SHALL render current weather details in a 320-pixel-wide weather panel.

#### Scenario: Weather panel has no data
- **WHEN** the weather panel is rendered without weather snapshot data
- **THEN** Alice SHALL render placeholder text similar to the notification panel's empty state
- **AND** Alice SHALL NOT throw layout or rendering errors

#### Scenario: Weather panel has current data
- **WHEN** the weather panel is rendered with weather snapshot data
- **THEN** Alice SHALL render three columns above the metrics card
- **AND** the first column SHALL show the current temperature in large font
- **AND** the second column SHALL show the current condition summary in medium font above a small metadata line
- **AND** the third column SHALL show the existing current-weather icon with its existing appearance
- **AND** Alice SHALL NOT repeat the condition summary in a separate row below the header
- **AND** Alice SHALL preserve the existing wind, humidity, and precipitation metrics card below the header without visual or behavioral changes

#### Scenario: Current metadata includes a location
- **WHEN** a nonblank configured weather location label is available
- **THEN** the metadata SHALL read `<location>, Current <HH:mm>`, for example `Boston, Current 18:37`
- **AND** the time SHALL be the current observation timestamp in the latest weather snapshot, interpreted in the API response timezone
- **AND** Alice SHALL NOT round the timestamp to a whole or even-numbered hour or substitute the wall-clock time

#### Scenario: Current metadata has no location
- **WHEN** the configured weather location label is absent or blank
- **THEN** the metadata SHALL read `Current <HH:mm>` without a leading comma

#### Scenario: Header text exceeds available space
- **WHEN** location or condition text does not fit the header
- **THEN** Alice SHALL bound wrapping or truncate text without overflowing the panel
- **AND** Alice SHALL retain the three-column ordering

#### Scenario: Current metrics are rendered
- **WHEN** current wind, humidity, and precipitation probability values are present
- **THEN** Alice SHALL render a wind-direction icon pointing toward the wind direction with wind speed and unit label below it
- **AND** Alice SHALL render a humidity icon bucketed by humidity ranges `[1,.75)`, `[.75,.5)`, `[.5,.25)`, and `[.25,0]` with the humidity percentage below it
- **AND** Alice SHALL render precipitation chance as a large percentage with the existing label `Precip.` below it

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
- **WHEN** Alice renders a daily forecast chart slot with moon phase data
- **THEN** Alice SHALL vary the night/moon icon according to the moon phase value

#### Scenario: Wind direction icon is rendered
- **WHEN** Alice renders a wind direction icon with a wind bearing
- **THEN** Alice SHALL round the bearing to the nearest 45 degrees
- **AND** Alice SHALL use a corresponding pre-rotated Phosphor direction icon such as west or north-west
- **AND** the icon SHALL indicate the direction the wind is blowing toward

## REMOVED Requirements

### Requirement: Weather forecast cards
**Reason**: Hourly and daily card carousels are replaced by continuous temperature charts with aligned annotations.
**Migration**: Render the same forecast data and existing icon mappings through the Weather forecast charts requirement. Replace card selection backgrounds with Now/Today labels, limit daily forecasts to seven days, and use 24-hour hourly labels.

## ADDED Requirements

### Requirement: Weather forecast charts
Alice SHALL render hourly and daily temperature forecasts as independently horizontally scrollable, theme-aware line charts below the unchanged metrics card.

#### Scenario: Hourly forecast is rendered
- **WHEN** the weather panel has hourly forecast entries
- **THEN** Alice SHALL render a left-aligned `Hourly` heading and an hourly temperature chart
- **AND** the displayed window SHALL begin with the closest hourly entry whose timestamp is less than or equal to now, or the first available entry when none qualifies
- **AND** Alice SHALL display up to 24 entries beginning at that entry
- **AND** the first slot SHALL be labeled `Now` and subsequent slots SHALL use `HH:mm` labels in the API response timezone
- **AND** each slot SHALL show its existing weather icon below its time label and one degree-labeled temperature below its icon
- **AND** valid temperatures SHALL be connected by an accent-colored line with faint fill underneath

#### Scenario: Daily forecast is rendered
- **WHEN** the weather panel has daily forecast entries
- **THEN** Alice SHALL render a plain left-aligned `Daily` heading and a daily temperature chart
- **AND** the High/Low key SHALL be within the chart section below the plot, not in the section heading
- **AND** Alice SHALL display up to seven daily entries beginning with the API-local date matching today
- **AND** if today is absent, the window SHALL begin with the first future date, or the first available entry when all data is in the past
- **AND** an entry matching today SHALL be labeled `Today` and other entries SHALL use localized abbreviated weekday labels
- **AND** each slot SHALL show its existing weather icon below its day label and high/low temperatures below its icon
- **AND** both values SHALL include degree symbols and the low value SHALL use a muted color
- **AND** highs and lows SHALL be plotted as separate lines on a shared temperature scale, with an accent-colored high line, muted low line, faint band between them, and a visible High/Low legend

#### Scenario: Chart presentation follows Alice's theme
- **WHEN** a forecast chart is rendered
- **THEN** Alice SHALL use the existing panel theme and weather icons rather than introducing illustrated weather assets or a separate background palette
- **AND** the plot SHALL use subtle vertical guides and SHALL NOT display numeric y-axis labels or duplicate time/day labels
- **AND** current entries SHALL be identified by Now/Today labels rather than highlighted card backgrounds
- **AND** approximately five slots SHALL be visible at once at the standard panel width when sufficient entries exist

#### Scenario: Forecast charts are scrolled
- **WHEN** the user scrolls a forecast chart horizontally, drags it, or uses the mouse wheel over it
- **THEN** Alice SHALL scroll that chart horizontally without changing the other chart's scroll position
- **AND** time/day labels, icons, temperature labels, and plotted samples SHALL scroll together and remain aligned
- **AND** Alice SHALL show a scrollbar while scrolling and hide it when not moving
- **AND** the overall panel SHALL fit its available width and height without overflow or scrolling; only forecast sections SHALL scroll horizontally

#### Scenario: Pointer interaction does not inspect data
- **WHEN** the user hovers, clicks, or taps a forecast plot
- **THEN** Alice SHALL NOT display tooltips, crosshairs, selection markers, or hover highlights
- **AND** this SHALL NOT disable scrolling gestures

#### Scenario: Forecast data is short or empty
- **WHEN** a forecast section has fewer entries than its limit
- **THEN** Alice SHALL render only the available entries without inventing forecast data
- **AND** an empty section SHALL show `No forecast data.` instead of a chart

#### Scenario: Temperatures are missing or constant
- **WHEN** forecast temperatures are absent, constant, or limited to one valid sample
- **THEN** Alice SHALL render without invalid-axis or layout errors
- **AND** missing temperatures SHALL retain the existing missing-value label and SHALL NOT be plotted as zero
- **AND** lines and daily fill bands SHALL break across missing data
- **AND** a lone valid sample SHALL remain visible
- **AND** a section with no valid temperatures SHALL retain its annotations and show an unavailable message in the plot area
