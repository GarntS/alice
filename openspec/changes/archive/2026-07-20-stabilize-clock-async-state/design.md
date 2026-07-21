## Context

`_ClockPanelState` in `lib/widgets/panels/clock_panel.dart` owns a selected date, displayed month, event result, loading flag, authorization timer, and month indicators. `_fetchEvents` and `_refreshIndicators` currently commit every completion. `_updatePollTimer` creates one periodic callback that closes over the `date` argument, so changing dates while authorization remains pending does not update the timer target. The production bridge is the generated `fetchCalendarEvents({required String date})`; focused tests currently avoid constructing `ClockPanel` because that dependency is fixed.

## Goals / Non-Goals

**Goals:**
- Ensure only the latest request for the active selected date controls `_fetchResult`, `_loading`, and polling status.
- Ensure only the latest request for the active displayed month controls `_indicators`.
- Make the authorization timer use the selected date at tick time.
- Make completion ordering deterministic under test without changing production construction.

**Non-Goals:**
- Change five-second polling cadence, calendar statuses, OAuth behavior, cache behavior, event ordering, indicator color extraction, or UI layout.
- Change native Rust, generated files, bridge signatures, configuration, dependencies, or persisted tokens.
- Add request cancellation to flutter_rust_bridge; stale completions are ignored locally.

## Decisions

### Inject the existing fetch function through an optional compatible seam

Add a function type matching the generated named-argument shape, for example `Future<CalendarFetchResult> Function({required String date})`, and an optional `ClockPanel` field whose default is the existing generated `fetchCalendarEvents` tear-off. Keep `ClockPanel`'s existing `config` and `snapshot` parameters and const construction valid. Tests can supply a fake returning controlled `Completer` futures.

This is preferred over initializing Rust in widget tests or introducing a calendar repository/service abstraction: only one operation needs substitution, and a larger layer would add more concepts than it removes.

### Use independent monotonically increasing request generations

Maintain one event-request generation and one indicator-request generation in `_ClockPanelState`. `_fetchEvents(date)` captures the incremented event generation before awaiting. It may commit only when mounted, its generation remains latest, and `date` still equals `_selectedDate` by calendar date. Only an accepted result may clear `_loading`, replace `_fetchResult`, update the polling timer, or trigger indicator refresh.

`_refreshIndicators(month)` similarly captures an incremented indicator generation and may replace `_indicators` only when mounted, still latest, and `month` still equals `_calendarMonth` by year/month. Keep the current parallel `Future.wait` and color extraction behavior.

Generation checks are preferred over comparing only dates/months because two requests for the same date can overlap; completion order must still be latest-request-wins.

### Make polling consult current state

Change `_updatePollTimer` to accept only the accepted `CalendarFetchResult`. Preserve its create-once behavior and five-second period, but have each timer callback invoke `_fetchEvents(_selectedDate)`. Continue cancelling and nulling the timer for statuses other than `polling` and `needs_auth`, and in `dispose`.

This is preferred over recreating the timer for every date selection because the cadence need not reset merely to update its target.

## Risks / Trade-offs

- [A stale request still consumes bridge/native work] → Ignore only its Flutter commit; cancellation is outside scope and the native cache already serves in-window dates.
- [A fake fetch seam broadens the widget surface] → Keep it optional, strongly typed, and defaulted to the existing bridge function so current callers and production behavior are unchanged.
- [Two selected changes edit `clock_panel.dart`] → This change is independently applicable; if `derive-calendar-grid-state` is applied first, preserve its derived-grid structure while adding only async ownership fields and checks.
- [A stale request leaves loading true] → Only the latest request owns `_loading`; tests must prove an older completion cannot clear it and the latest completion does.
