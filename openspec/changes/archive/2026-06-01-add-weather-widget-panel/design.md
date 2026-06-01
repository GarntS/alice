## Context

Alice streams Rust-owned system state to Flutter through `BarSnapshot` and renders independent bar modules plus native-hosted panel windows. Configuration is loaded once from `$XDG_CONFIG_HOME/alice/config.yaml` or `$HOME/.config/alice/config.yaml`, mapped through flutter_rust_bridge, and is generally restart-scoped.

Weather adds a new external data source, a new optional snapshot subtree, a new top bar module, and a new panel. The feature must not make Alice unavailable: disabled weather is ignored entirely, while missing credentials, invalid coordinates, request failures, parse failures, and HTTP failures are Rust-log-only conditions. When a previous successful response exists, it remains usable as stale cached data after later failures.

## Goals / Non-Goals

**Goals:**
- Add a top-level `weather` config section with documented defaults and validation.
- Fetch Pirate Weather forecast data immediately at startup and periodically thereafter.
- Cache only the most recent successful response in Rust and expose it as optional weather data on `BarSnapshot`.
- Keep weather values mostly API-shaped in Rust/FRB models and perform presentation formatting in Flutter.
- Render an enabled weather widget and panel, including no-data placeholders, current conditions, metrics, hourly cards, and daily cards.
- Add concise fixture/render tests for no-data and has-data paths.

**Non-Goals:**
- No geolocation, location search, or automatic coordinate discovery.
- No user-facing weather error UI beyond placeholder/no-data rendering.
- No alerts UI, even though alerts are requested and cached in the model for future use.
- No runtime config reload; weather config changes require restart like current config behavior.
- No long-term persistence of weather responses across process restarts.

## Decisions

### Use a restart-scoped weather config

Weather configuration is parsed with the rest of Alice config and is not watched for live changes. This matches existing behavior and avoids rebuilding runtime tasks when API keys, coordinates, or refresh intervals change.

Alternative considered: live reload weather config. Rejected to keep the change consistent with current config semantics.

### Default enabled, but failure-tolerant

`weather.enable` defaults to `true`. If enabled but required fields are absent, empty, or invalid, Rust logs a redacted configuration error and the app continues. If `weather.enable` is `false`, weather validation and runtime tasks are skipped entirely.

Alternative considered: default disabled to avoid log errors for existing users. Rejected because the requested semantics explicitly make weather enabled unless disabled.

### Separate fetch/client parsing from cached provider state

The implementation should keep Pirate Weather request construction, HTTP execution, response-status handling, and JSON parsing behind a small client/test boundary. Runtime-owned weather cache state then exposes `Option<WeatherSnapshot>` for snapshot assembly.

This keeps tests network-free: parser/client behavior can use the sample fixture, while snapshot aggregation can use a fake weather provider.

### Keep model data API-shaped, format in Flutter

Rust should expose numeric fields such as temperature, humidity, precipitation probability, wind speed, wind bearing, moon phase, timestamps, timezone, and forecast arrays in near-API form. Flutter formats degree labels, percentages, wind units, weekday/hour labels, card text, and icon selection.

Alternative considered: preformatted strings in Rust. Rejected because UI formatting decisions belong with Flutter widgets and can evolve without changing API parsing.

### Cache the latest successful response only

The weather runtime cache stores the full latest successful response mapped into Alice weather structs. Failed refreshes do not clear the cache; they log a specific error and wait until the next configured interval. New successful responses replace the previous response entirely; hourly/daily entries are not merged across responses.

Alternative considered: persisting cached weather to disk. Rejected as unnecessary for a bar widget and outside the requested scope.

### Request Pirate Weather with minutely excluded and alerts retained

Requests use the configured API key, latitude, longitude, language, units, and `version=2`, exclude minutely data, and do not exclude alerts. Alerts remain unused in UI but are cached in Rust/Flutter data models for future expansion.

### Use Material Icons and deterministic icon mapping

Flutter uses Material Icons for weather, wind, humidity, and precipitation. Pirate Weather icon strings map to an initial Material icon set that can be refined later. Moon icons vary by `moonPhase` when available. Wind direction is rounded to the nearest 45 degrees and shown as a pre-rotated Material direction icon indicating the direction the wind is blowing toward.

### Make weather a normal panel identity

Weather joins the existing panel controller as a mutually-exclusive panel. It uses width 320, right alignment from the top bar cluster, and a height constrained by screen height with a minimum/placeholder no-data presentation.

## Risks / Trade-offs

- Existing users without `weather` config will see Rust log errors because weather defaults enabled → Document the default config clearly and keep the app/UI operational.
- API keys could appear in URLs or errors → Centralize request/error logging and redact keys before printing.
- Pirate Weather fields may be missing or contain sentinel values such as `-999` → Treat sentinel values as absent and make optional fields render defensively.
- Weather refresh shares the snapshot stream with high-frequency metrics triggers → Only emit weather-driven snapshot changes when cached weather data changes, and rely on Flutter snapshot-state equality to avoid unrelated rebuilds.
- Horizontal forecast lists may overflow small screens → Use fixed-width cards, horizontal scrolling, fading/truncating text, and cap hourly display to 24 cards.
- Adding `intl` increases Flutter dependencies → Limit usage to weekday/hour labels and keep formatting local to weather UI.
