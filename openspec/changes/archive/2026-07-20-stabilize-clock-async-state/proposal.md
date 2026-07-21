## Why

`ClockPanel` currently commits calendar fetches in completion order and lets its authorization timer retain the date that created it. Rapid date/month changes can therefore display stale events or indicators and continue polling the wrong date; making active-request ownership explicit removes that hidden temporal coupling.

## What Changes

- Apply a calendar event result only while it still belongs to the currently selected date and latest event request.
- Make authorization polling fetch the current selected date rather than a date captured when the timer was first created.
- Apply month indicators only while they still belong to the currently displayed month and latest indicator request.
- Add deterministic widget coverage using a controllable calendar-fetch seam.
- Preserve the existing generated `fetchCalendarEvents` API as the production default and preserve all status, polling, rendering, and disposal behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clock-world-clock-calendar`: Require asynchronous event, authorization-polling, and indicator results to remain aligned with the active selected date and displayed month.

## Impact

- Primary code: `lib/widgets/panels/clock_panel.dart`, especially `ClockPanel`, `_ClockPanelState._fetchEvents`, `_updatePollTimer`, `_onDateSelected`, and `_refreshIndicators`.
- Tests: `test/panels_rendering_test.dart` or a new focused clock-panel test under `test/`.
- Public compatibility: the existing `ClockPanel(config:, snapshot:)` construction remains valid; any fetch seam is optional and defaults to the generated bridge function.
- No Rust, generated binding, protocol, persisted format, dependency, configuration, or unrelated panel changes.
