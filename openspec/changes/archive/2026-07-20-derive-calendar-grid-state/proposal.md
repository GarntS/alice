## Why

`AliceCalendar` stores month rows and “today” alongside the displayed month even though both are derived values, forcing navigation code to synchronize parallel state and allowing “today” to become stale. Deriving this small fixed grid directly makes the state model lighter and its invariants obvious.

## What Changes

- Retain only the displayed month as mutable calendar-grid state.
- Derive the six-by-seven date grid and current day when rendering.
- Replace the single-field `_CalendarDay` wrapper with direct `DateTime` cells and derive indicator keys where used.
- Add focused coverage for grid boundaries, navigation callbacks, selection, today highlighting, and indicators.
- Preserve all existing calendar layout and interaction behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clock-world-clock-calendar`: Clarify the fixed Sunday-first month-grid behavior and require the today state to reflect the current date rather than initialization time.

## Impact

- Primary code: `lib/widgets/panels/clock_panel.dart`, specifically `_CalendarDay`, `_AliceCalendarState`, `_buildMonthRows`, and `_DayCell`.
- Tests: `test/panels_rendering_test.dart` or a new focused `AliceCalendar` test under `test/`.
- No changes to `ClockPanel` event fetching, Google authorization, native Rust, generated bindings, public constructor signatures, dependencies, styling, or other panels.
