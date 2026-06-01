## 1. Configuration and Dependencies

- [x] 1.1 Add Flutter `intl` dependency and refresh lockfiles/generated package config as needed.
- [x] 1.2 Add Rust HTTP/JSON dependency support needed for Pirate Weather requests and response parsing.
- [x] 1.3 Extend Rust config structs and raw YAML parsing with `weather.enable`, `pirate_weather_key`, `forecast_lat`, `forecast_long`, `forecast_language`, `forecast_units`, and `refresh_interval`.
- [x] 1.4 Implement weather defaults, disabled-weather bypass, coordinate validation, empty-key validation, refresh interval minimum of 300 seconds, and redacted Rust log errors.
- [x] 1.5 Extend Flutter `AliceConfig` and config mapping with typed weather settings.
- [x] 1.6 Update the shipped default `assets/config/default_config.yaml` with documented weather keys and defaults.
- [x] 1.7 Add config unit tests for omitted weather config, disabled incomplete weather config, valid weather config, invalid coordinates, and refresh interval clamping.

## 2. Rust Weather Data and Pirate Weather Client

- [x] 2.1 Define Rust weather snapshot structs for response metadata, current conditions, hourly entries, daily entries, alerts, and optional/sentinel-cleaned numeric values.
- [x] 2.2 Add a Pirate Weather sample JSON fixture based on the provided response.
- [x] 2.3 Implement Pirate Weather URL construction using configured key, coordinates, language, units, `exclude=minutely`, and `version=2`.
- [x] 2.4 Implement the Pirate Weather client/parser boundary with distinct redacted errors for transport failures, HTTP status failures, JSON parse failures, and missing required fields.
- [x] 2.5 Parse current, hourly, daily, alerts, latitude, longitude, timezone, units, and last-updated data into the weather structs.
- [x] 2.6 Add parser/client tests using the fixture without live network access.

## 3. Snapshot Runtime Integration

- [x] 3.1 Add optional weather data to Rust `BarSnapshot` and export it through the FRB API surface.
- [x] 3.2 Add a weather provider/cache abstraction that can return `Option<WeatherSnapshot>` without doing HTTP during snapshot assembly.
- [x] 3.3 Start a weather refresh task when weather is enabled and valid, fetch immediately, then refresh on interval plus small jitter.
- [x] 3.4 Preserve the most recent successful cached weather data after refresh failures and log failures without immediate retry.
- [x] 3.5 Emit snapshot triggers when cached weather changes.
- [x] 3.6 Extend testable snapshot aggregation with fake weather provider support and fallback-to-none behavior.
- [x] 3.7 Regenerate flutter_rust_bridge Rust and Dart bindings for updated config and state models.

## 4. Flutter Snapshot State and Panel Controller

- [x] 4.1 Extend generated/consumed Dart weather models after FRB regeneration and update `AlicePlatform` snapshot stabilization/reconstruction to include weather.
- [x] 4.2 Add weather value notifier, current weather accessor, equality helpers, and ingest behavior to `AliceSnapshotState`.
- [x] 4.3 Add `AlicePanel.weather`, panel id mapping, granular weather open-state notifier, and weather toggle support to `PanelController`.
- [x] 4.4 Add weather panel sizing at width 320 with screen-height constraints and a minimum no-data placeholder height.
- [x] 4.5 Wire weather panel sync/listeners into `AliceApp`, panel id generation, and `AlicePanelCard` content dispatch.

## 5. Weather Bar Widget

- [x] 5.1 Create a top bar weather module that renders to the right of the clock when weather is enabled.
- [x] 5.2 Render current weather icon plus API temperature value with degree symbol when weather data exists.
- [x] 5.3 Render cloud icon plus `-` while enabled with no data.
- [x] 5.4 Add `Last Updated <timestamp>` tooltip using the cached last-updated timestamp when available.
- [x] 5.5 Hook weather widget taps to toggle the weather panel and reflect highlighted/open state.

## 6. Weather Panel UI

- [x] 6.1 Create weather panel layout with no-data placeholder text and no render errors when snapshot weather is absent.
- [x] 6.2 Render current conditions top row with large icon, large temperature, and lighter summary text.
- [x] 6.3 Render metrics card with wind direction/speed, humidity bucket/percentage, and precipitation chance percentage.
- [x] 6.4 Implement Material icon mapping for Pirate Weather icon strings, humidity buckets, wind direction rounded to nearest 45 degrees, and moon phase variation.
- [x] 6.5 Implement Flutter-side formatting for degree labels, percentage labels, wind unit labels, and API-timezone timestamps.
- [x] 6.6 Render hourly section with up to 24 fixed-width cards, `Now` selection, accent background, contrasting colors, and single temperature values.
- [x] 6.7 Render daily section with fixed-width cards, `Today`/three-letter weekday labels via `intl`, accent background for today, and high/low temperatures.
- [x] 6.8 Add horizontal scrolling with mouse wheel support and scrollbars that appear while scrolling.
- [x] 6.9 Ensure card text fades or truncates without overflow.

## 7. Tests and Verification

- [x] 7.1 Add/extend Flutter widget tests for top bar rendering with no weather data and with weather data.
- [x] 7.2 Add/extend Flutter panel tests for weather panel no-data and has-data rendering without errors.
- [x] 7.3 Add/extend panel controller tests for weather panel identity, toggle behavior, and granular open-state notifications.
- [x] 7.4 Run Rust tests for config, parser, and snapshot aggregation.
- [x] 7.5 Run Flutter tests for bar, panel, snapshot state, and controller behavior.
- [x] 7.6 Run FRB/codegen validation and ensure generated files are committed.
