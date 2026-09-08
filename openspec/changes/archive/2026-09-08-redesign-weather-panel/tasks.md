## 1. Chart dependency and presentation helpers

- [x] 1.1 Add a compatible stable `fl_chart` dependency and resolve the Flutter lockfile without changing backend dependencies.
- [x] 1.2 Add testable header timestamp formatting using the current observation time, API timezone offset, and unrounded `HH:mm`; handle absent/blank location labels.
- [x] 1.3 Add forecast-window selection for up to 24 hours starting at Now and up to seven days starting at today, including future-only and stale-data fallbacks.
- [x] 1.4 Add plot-data preparation for shared slot coordinates, padded temperature ranges, missing-value gaps, and constant/single-point data.

## 2. Current-condition header

- [x] 2.1 Reorganize `_CurrentHeader` into large temperature, flexible summary/metadata, and existing weather icon columns; remove the standalone summary below it.
- [x] 2.2 Preserve `_MetricsCard` and its existing labels, metrics, styles, and behavior; bound header wrapping/truncation at the standard panel width.
- [x] 2.3 Add header widget/formatting tests covering column order, relative text sizes, timestamp minutes and timezone conversion, stale data, absent location, long text, and metrics-card regression protection.

## 3. Shared scrollable chart surface

- [x] 3.1 Build a reusable horizontal chart surface with aligned annotation slots and plot coordinates, roughly five visible slots, and independent per-section controllers.
- [x] 3.2 Preserve horizontal wheel/drag scrolling and transient scrollbars while keeping outer vertical panel scrolling usable.
- [x] 3.3 Apply Alice theme colors, subtle vertical guides, hidden numeric/duplicate axes, and disabled chart touch/hover feedback.

## 4. Hourly and daily forecasts

- [x] 4.1 Replace hourly cards with Now/HH:mm labels, existing weather icons, degree labels, and a single accent line with faint area fill for the selected 24-hour window.
- [x] 4.2 Replace daily cards with Today/weekday labels, existing moon-phase-aware icons, high/low degree labels, two lines with a faint band, and a High/Low key below the plot (not in the section heading) for the selected seven-day window.
- [x] 4.3 Preserve Hourly/Daily headings and empty states; handle missing temperatures, broken series/bands, and lone samples without fabricated values.
- [x] 4.4 Remove obsolete forecast-card rendering and unused carousel-specific code after both charts use the shared surface.

## 5. Verification

- [x] 5.1 Test forecast limits and selection, timezone/day rollover, 24-hour formatting, abbreviated weekdays, units, missing values, and empty/short/constant/single-point datasets.
- [x] 5.2 Add widget tests for both chart series, annotation alignment before/after scrolling, independent scroll positions, wheel/drag behavior, and absence of hover/tap feedback.
- [x] 5.3 Visually verify the header, unchanged metrics card, five-slot chart density, fill/band contrast, and legend in light/dark themes and with enlarged text at the existing panel width.
- [x] 5.4 Run formatting checks, Flutter analysis, focused tests, and the full Flutter test suite; use `nix develop --command ...` if NixOS tooling is required.
