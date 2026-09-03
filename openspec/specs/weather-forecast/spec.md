# weather-forecast Specification

## Purpose
TBD - created by archiving change add-weather-widget-panel. Update Purpose after archive.
## Requirements
### Requirement: Weather configuration controls collection
Alice SHALL support a top-level `weather` configuration section that controls Pirate Weather collection and UI availability.

#### Scenario: Weather is disabled
- **WHEN** `weather.enable` is set to `false`
- **THEN** Alice SHALL skip weather credential and coordinate validation
- **AND** Alice SHALL make no Pirate Weather requests
- **AND** Alice SHALL hide the weather bar widget

#### Scenario: Weather enable is omitted
- **WHEN** the `weather` section omits `enable`
- **THEN** Alice SHALL treat weather as enabled

#### Scenario: Required weather fields are missing while enabled
- **WHEN** weather is enabled and `weather.pirate_weather_key`, `weather.forecast_lat`, or `weather.forecast_long` is missing or empty
- **THEN** Alice SHALL print a redacted error to the Rust logs
- **AND** Alice SHALL continue running the app
- **AND** Alice SHALL expose no weather data until a valid configuration is provided on a later restart

#### Scenario: Weather coordinate values are invalid
- **WHEN** weather is enabled and latitude is outside `-90..90` or longitude is outside `-180..180`
- **THEN** Alice SHALL print a validation error to the Rust logs
- **AND** Alice SHALL continue running the app
- **AND** Alice SHALL expose no weather data

#### Scenario: Optional weather fields are omitted
- **WHEN** weather is enabled and optional fields are omitted
- **THEN** Alice SHALL default `forecast_language` to `en`
- **AND** Alice SHALL default `forecast_units` to `us`
- **AND** Alice SHALL default `refresh_interval` to `3600`

#### Scenario: Refresh interval is too low
- **WHEN** weather is enabled and `weather.refresh_interval` is less than `300`
- **THEN** Alice SHALL use `300` seconds as the effective refresh interval

### Requirement: Pirate Weather requests
Alice SHALL request forecast data from Pirate Weather using the configured API key, coordinates, language, units, and API version.

#### Scenario: Weather fetch starts
- **WHEN** weather is enabled and configuration is valid
- **THEN** Alice SHALL fetch weather immediately after the snapshot runtime starts
- **AND** Alice SHALL fetch again every effective refresh interval with a small jitter of a few seconds

#### Scenario: Request URL is constructed
- **WHEN** Alice requests Pirate Weather data
- **THEN** Alice SHALL request `https://dev.pirateweather.net/forecast/<key>/<lat>,<long>`
- **AND** Alice SHALL include `exclude=minutely`
- **AND** Alice SHALL include `version=2`
- **AND** Alice SHALL include the configured language and units query values
- **AND** Alice SHALL redact the API key from any logged URL or error text

#### Scenario: Alerts are returned
- **WHEN** Pirate Weather returns alerts in the response
- **THEN** Alice SHALL cache the alert data in the Rust and Flutter weather data models
- **AND** Alice SHALL NOT render alert UI for this change

### Requirement: Weather error handling and cache behavior
Alice SHALL keep the app running and preserve the latest successful weather data when weather collection fails.

#### Scenario: Initial weather request fails
- **WHEN** the first weather request fails due to an HTTP status, transport error, JSON parse error, or missing required response field
- **THEN** Alice SHALL print an error message that distinguishes the failure category to the Rust logs
- **AND** Alice SHALL expose no weather data
- **AND** Alice SHALL wait until the next effective refresh interval before retrying

#### Scenario: Refresh fails after previous success
- **WHEN** Alice has cached a successful weather response and a later refresh fails
- **THEN** Alice SHALL print an error message that distinguishes the failure category to the Rust logs
- **AND** Alice SHALL keep exposing the previous successful weather data as stale cached data
- **AND** Alice SHALL wait until the next effective refresh interval before retrying

#### Scenario: Refresh succeeds after previous success
- **WHEN** Alice receives a new successful Pirate Weather response
- **THEN** Alice SHALL replace the previously cached response with the new response
- **AND** Alice SHALL NOT merge hourly, daily, or alert entries across responses

### Requirement: Weather snapshot data
Alice SHALL expose optional weather data in the bar snapshot using mostly API-shaped values.

#### Scenario: Weather data is available
- **WHEN** Alice has a successful Pirate Weather response
- **THEN** the weather snapshot SHALL include response latitude, longitude, timezone, last-updated timestamp, current conditions, hourly forecast entries, daily forecast entries, and alerts
- **AND** current conditions SHALL include summary, icon, temperature, humidity, precipitation probability, wind speed, and wind bearing when present
- **AND** hourly entries SHALL include timestamp, summary, icon, temperature, humidity, precipitation probability, wind speed, and wind bearing when present
- **AND** daily entries SHALL include timestamp, summary, icon, moon phase, temperature high, temperature low, humidity, precipitation probability, wind speed, and wind bearing when present

#### Scenario: Sentinel values are parsed
- **WHEN** Pirate Weather returns sentinel values such as `-999`
- **THEN** Alice SHALL treat those values as absent in the weather snapshot model

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

### Requirement: Weather panel current conditions
Alice SHALL render current weather details in a 320-pixel-wide weather panel.

#### Scenario: Weather panel has no data
- **WHEN** the weather panel is rendered without weather snapshot data
- **THEN** Alice SHALL render placeholder text similar to the notification panel's empty state
- **AND** Alice SHALL NOT throw layout or rendering errors

#### Scenario: Weather panel has current data
- **WHEN** the weather panel is rendered with weather snapshot data
- **THEN** Alice SHALL render a top row with a large current-weather icon on the left and the current temperature on the right
- **AND** Alice SHALL render the current summary below the top icon and temperature using a lighter font weight
- **AND** Alice SHALL render a metrics card below the summary with wind, humidity, and precipitation chance columns

#### Scenario: Current metrics are rendered
- **WHEN** current wind, humidity, and precipitation probability values are present
- **THEN** Alice SHALL render a wind-direction icon pointing toward the wind direction with wind speed and unit label below it
- **AND** Alice SHALL render a humidity icon bucketed by humidity ranges `[1,.75)`, `[.75,.5)`, `[.5,.25)`, and `[.25,0]` with the humidity percentage below it
- **AND** Alice SHALL render precipitation chance as a large percentage with the label `Precip. Chance` below it

### Requirement: Weather forecast cards
Alice SHALL render hourly and daily forecast entries as horizontally-scrollable fixed-width weather cards.

#### Scenario: Hourly cards are rendered
- **WHEN** the weather panel has hourly forecast entries
- **THEN** Alice SHALL render a left-aligned `Hourly` label
- **AND** Alice SHALL render up to 24 hourly weather cards from the latest response
- **AND** each hourly card SHALL show one temperature value with no low temperature
- **AND** the `Now` card SHALL be the closest hourly entry whose timestamp is less than or equal to the current timestamp in the API response timezone, or the first hourly entry when none are less than or equal
- **AND** the `Now` card SHALL use Alice's accent color with contrasting text and icon color

#### Scenario: Daily cards are rendered
- **WHEN** the weather panel has daily forecast entries
- **THEN** Alice SHALL render a left-aligned `Daily` label
- **AND** Alice SHALL render one daily weather card for each daily entry from the latest response
- **AND** the first API-timezone date matching today SHALL be labeled `Today`
- **AND** subsequent daily cards SHALL use three-letter weekday labels from Dart `intl`
- **AND** the `Today` card SHALL use Alice's accent color with contrasting text and icon color

#### Scenario: Weather card content is rendered
- **WHEN** Alice renders a weather forecast card
- **THEN** the card SHALL render an optional centered label at the top
- **AND** the card SHALL render a weather icon below the label
- **AND** the card SHALL render centered temperature text below the icon
- **AND** when both high and low temperatures are displayed, both values SHALL include degree symbols, the low value SHALL use a lighter font color, and the combined high-low group SHALL be centered
- **AND** text that does not fit SHALL fade or truncate without overflowing

#### Scenario: Forecast lists are scrolled
- **WHEN** the user scrolls a forecast card list horizontally or with the mouse wheel
- **THEN** Alice SHALL scroll the forecast cards horizontally
- **AND** Alice SHALL show a scrollbar while scrolling and hide it when not moving

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

### Requirement: Weather units and formatting
Alice SHALL format weather display values in Flutter using the configured Pirate Weather units.

#### Scenario: Weather values are displayed
- **WHEN** Flutter displays temperature, humidity, precipitation probability, and wind values
- **THEN** temperature SHALL use the API numeric value followed by a degree symbol
- **AND** humidity SHALL display the API fraction as a rounded percentage
- **AND** precipitation probability SHALL display the API fraction as a rounded percentage
- **AND** timestamps SHALL be interpreted in the API response timezone

#### Scenario: Wind units are displayed
- **WHEN** Flutter displays wind speed
- **THEN** `ca` units SHALL display wind speed in `km/h`
- **AND** `uk` units SHALL display wind speed in `mph`
- **AND** `us` units SHALL display wind speed in `mph`
- **AND** `si` units SHALL display wind speed in `m/s`

