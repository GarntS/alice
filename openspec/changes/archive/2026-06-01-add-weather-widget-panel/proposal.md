## Why

Alice currently has no first-class weather surface in the bar or panels. Adding Pirate Weather integration gives users at-a-glance current conditions and short-range forecasts without leaving the desktop shell.

## What Changes

- Add configurable Pirate Weather forecast collection driven by a new top-level `weather` section in `config.yaml`.
- Fetch weather immediately on startup and then every configured refresh interval, with a minimum interval of 300 seconds and a small jitter.
- Cache the most recent successful Pirate Weather response data in Rust and expose it through the bar snapshot as optional weather data.
- Render a weather bar widget to the right of the clock, showing a weather icon and current temperature, and toggle a weather panel when clicked.
- Render a weather panel with current conditions, current summary, wind/humidity/precipitation metrics, hourly forecast cards, and daily forecast cards.
- Preserve app availability when weather is disabled, misconfigured, or failing: log Rust errors, keep the app running, and render only no-data placeholders or stale cached data as applicable.
- Add the Flutter `intl` dependency for API-timezone-aware weekday labels in forecast cards.

## Capabilities

### New Capabilities
- `weather-forecast`: Pirate Weather configuration, collection, cached snapshot data, bar widget, and weather panel presentation.

### Modified Capabilities
- `configuration`: Add typed `weather` config parsing, defaults, validation rules, and default template documentation.
- `snapshot-runtime`: Add optional weather data to `BarSnapshot` and weather refresh triggers/provider behavior.
- `panel-controller`: Add weather as a supported panel identity with sizing, toggling, and highlight state.

## Impact

- Rust native platform crate: config model/parsing, weather API client/parser, runtime refresh task, cached provider state, snapshot model, FRB-generated bindings.
- Flutter app: config mapping, snapshot state, top bar weather module, panel controller, panel sizing, weather panel UI, Material icon mapping, `intl` date labels.
- Dependencies: add Rust HTTP/JSON support as needed for Pirate Weather requests and add Flutter `intl`.
- Tests/fixtures: add a Pirate Weather JSON fixture plus no-data and has-data render coverage.
