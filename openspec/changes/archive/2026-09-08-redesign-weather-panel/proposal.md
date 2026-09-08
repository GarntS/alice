## Why

The weather panel separates its current-condition summary from the temperature and presents forecasts as isolated cards, making temperature trends harder to scan. A compact three-column header and continuous, scrollable forecast charts will improve at-a-glance reading while retaining familiar weather labels and icons.

## What Changes

- Replace the area above the metrics card with three columns: large temperature; medium condition summary above a small city/current/data-time line; existing weather icon.
- Format the current weather data timestamp as unrounded `HH:mm` in the weather location's time, for example `Boston, Current 18:37`.
- Leave the wind/humidity/precipitation metrics card unchanged.
- Replace both forecast carousels with independently horizontally scrollable charts using Flutter's `fl_chart` package.
- Show up to 24 hourly entries starting at `Now`, followed by 24-hour time labels, existing weather icons, temperature labels, and an accent-colored temperature line with faint fill.
- Show up to seven daily entries starting at today, with weekday labels, existing icons, high/low labels, two temperature lines, a faint band between them, and a High/Low legend.
- Keep roughly five forecast slots visible, synchronize labels and plots within each scroller, and disable chart hover/touch feedback.
- Adapt the reference layout to Alice's theme rather than introducing illustrated icons or a separate color scheme.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `weather-forecast`: Revise current-condition layout and replace forecast-card requirements with labeled, scrollable hourly and daily temperature charts while preserving weather icon mappings and metrics behavior.

## Impact

- Flutter weather panel components in `lib/widgets/panels/weather_panel.dart`, weather formatting helpers as needed, and widget/formatting tests.
- Add `fl_chart` to `pubspec.yaml` and update the dependency lockfile during implementation.
- No Rust collection, API, configuration, or generated bridge changes are intended.
- The weather bar widget, metrics card, existing units, and icon mappings remain unchanged.
