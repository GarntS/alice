## Context

See proposal.md for motivation and scope. `lib/widgets/panels/weather_panel.dart` currently places a 64-pixel condition icon beside the city and temperature, followed by a separate summary. `_MetricsCard` follows, then hourly and daily fixed-width card lists. The list wrapper already supports mouse-wheel translation and pointer dragging inside the vertically scrolling panel.

Weather snapshots already contain current observation time, hourly/daily timestamps and temperatures, the API timezone offset, and a separate local fetch-completion timestamp. The configured location label is optional. `fl_chart` is not yet a dependency. No data-model changes are needed.

## Goals / Non-Goals

**Goals:**
- Keep layout changes inside the weather panel, with testable presentation/selection helpers where useful.
- Maintain label/icon/plot alignment throughout scrolling at the existing 320-pixel panel width.
- Handle missing temperatures and short forecasts without fabricated data or layout exceptions.

**Non-Goals:**
- Changing the metrics card, weather bar widget, collection cadence, configuration, unit conversion, or icon mapping.
- Tooltips, selection, crosshairs, hover highlights, zoom, or chart gestures beyond scrolling.
- New illustrated weather assets or a screenshot-specific background palette.

## Decisions

### 1. Three-column current header

Use content-sized temperature and icon columns around a flexible text column, vertically centered. Retain the current icon descriptor and 64-pixel size. Keep the temperature large, condition summary medium, and metadata small/muted; remove the separate summary below the header. Equal-width columns would waste space and constrain the metadata unnecessarily.

Use the configured location label as the city text. When absent or blank, show `Current HH:mm` without a dangling comma. Use the latest snapshot's `currently.time` observation timestamp, formatted with the existing API-offset conversion and `HH:mm`. Do not round it to an hour or substitute the wall clock or fetch-completion timestamp. Preserve temperature units, but render the header F/C suffix at 45% of the main temperature font size. Allow bounded summary wrapping and metadata ellipsis rather than overflow.

```text
24°     Breezy                      [existing icon]
        Boston, Current 18:37

+------------------------------------------------+
|       Existing metrics card — unchanged        |
+------------------------------------------------+

Hourly
Now       19:00      20:00      21:00      22:00
[icon]    [icon]     [icon]     [icon]     [icon]
24°       23°        22°        21°        20°
   temperature line with faint area fill → scroll

Daily
Today     Tue        Wed        Thu        Fri
[icon]    [icon]     [icon]     [icon]     [icon]
24°/16°   22°/15°    25°/17°    23°/16°   24°/17°
   high and low lines with faint band → scroll
High / Low
```

### 2. Use fl_chart for plots and Flutter widgets for annotations

Add a compatible stable `fl_chart` dependency during implementation and use its line chart for the temperature plot. Keep time/day labels, existing `AliceIcon` widgets, and degree labels in an aligned annotation row above the plot. This preserves icon and text behavior without forcing rich annotation content into chart axis labels. Do not introduce a custom canvas renderer instead of the requested chart package.

Each section owns one horizontal scroll controller and one shared content width for annotations and plot, with roughly five slots visible at the standard panel width. Map each point to its slot center, including half-slot leading/trailing padding. Labels and line must scroll as one surface; separate synchronized controllers are unnecessary and risk drift. Keep Hourly/Daily headings plain and outside the scrollers. Place the daily High/Low key below the plot within the chart section, using wrapping when needed for enlarged text; do not put a legend in the section heading. Preserve wheel-to-horizontal scrolling, touch/mouse dragging, and transient scrollbars inside forecasts only. The overall panel must not scroll or overflow. Stretch content to the host's inner width (288×572 inside the standard padded 320×600 host). Keep header and metrics at their natural sizes and divide remaining height between forecast sections. Adapt plot heights and fit annotations within their slots when height is constrained; never uniformly scale the whole panel, which would shrink its width.

### 3. Select bounded forecast windows before rendering

For hourly data, select the most recent entry at or before now, falling back to the first entry when none qualifies. Start the displayed window at that entry, label it `Now`, and take up to 24 entries. Subsequent labels use `HH:mm` in API-local time. Do not invent an observation point from current conditions.

For daily data, start at the entry whose API-local date is today and take up to seven entries; if today is absent, start at the first future date, or the first available entry for entirely stale data. Only an actual today date receives `Today`; other dates use localized abbreviated weekday labels. Render fewer slots when fewer entries exist rather than padding with invented forecasts.

### 4. Theme-aware noninteractive plots

Hourly uses one accent-colored line and a faint fill beneath it. Daily uses an accent high line, a lighter accent-derived low line, a faint band between them, a faint fill below the low line based on its color, and a small color-keyed High/Low legend. Continue to show both degree labels above each daily point, with the low label muted. Keep existing daily moon-phase icon handling.

Use straight segments with rounded strokes between samples, rasterized at twice the layout resolution and filtered down for smoother edges without adding forecast samples, subtle vertical guides, no numeric y-axis or duplicate chart x-axis labels, and no card-shaped Now/Today highlight. Labels identify the current slot. Use independent padded numeric y-ranges for hourly and daily plots; both daily series share one range. Straight segments avoid spline overshoot and imply no additional forecast precision.

Disable built-in chart touch handling so hovering, clicking, and tapping produce no tooltips, indicators, or selection. Scrolling remains enabled via the surrounding Flutter scroll surface.

### 5. Missing and degenerate data

Retain the existing panel unavailable state and per-section `No forecast data.` state. Keep slots with missing temperature labels using the existing missing-value formatting, but omit invalid plotted values and break lines/bands across gaps rather than interpreting absence as zero. Use finite padded axis ranges for constant or single-point data; make a lone valid sample visible with a point marker. With no valid temperatures, retain annotations and show a plot-area unavailable message instead of misleading geometry.

## Risks / Trade-offs

- [Long city names, summaries, or large temperature text compete in a narrow header] → Use a flexible middle column, bounded wrapping/ellipsis, and narrow-width/text-scaling regression tests.
- [Chart and annotation coordinates drift] → Derive both from one slot width and shared half-slot padding; test alignment before and after scrolling.
- [New chart dependency conflicts with the project's Flutter/material_ui stack] → Resolve a compatible stable release and run analyzer/widget tests before committing dependency changes.
- [Chart gesture recognizers consume forecast scrolling] → Disable chart touch handling and test wheel, drag, and outer vertical scrolling.
- [Sparse data or equal temperatures create invalid axes] → Compute finite padded ranges from valid values and test zero/one/multiple valid samples.
- [Cached weather timestamps remain old after a failed refresh] → Intentionally display the data timestamp, not a freshly generated clock label; collection/cache policy remains unchanged.
- [Muted low line loses contrast] → Check both light/dark themes and pair line colors with an explicit High/Low legend.

## Follow-up theme correction

User review identified that cards throughout the app used hard-coded warm beige rather than the configured accent. Derive the shared `raisedContainer` token from the accent over the surface (10% in light mode, 16% in dark mode). The metrics card layout and behavior remain unchanged; its background follows this intentional app-wide palette correction.

## Migration Plan

No persistent-data or configuration migration is required. Add the dependency, implement the header and forecast presentation, and run focused and full Flutter checks. Rollback consists of reverting the UI and dependency changes; backend snapshots remain compatible.
