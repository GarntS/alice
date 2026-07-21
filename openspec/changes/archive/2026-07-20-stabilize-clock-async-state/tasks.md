## 1. Deterministic Async Coverage

- [x] 1.1 Add a strongly typed optional calendar-fetch seam to `ClockPanel` that defaults to generated `fetchCalendarEvents`, and build test helpers that can complete date requests in a chosen order without initializing Rust.
- [x] 1.2 Add a widget regression where date A remains pending, date B is selected and completed, then A completes; assert B remains visible and the older completion does not own loading, result, polling, or indicators.
- [x] 1.3 Add timer coverage where polling starts for date A, date B is selected, five seconds elapse, and the timer requests B; verify an accepted non-polling result stops further ticks.
- [x] 1.4 Add month-indicator coverage where an older month's `Future.wait` completes after the current month and cannot replace current indicators, plus disposal coverage for pending work.

## 2. Active Request Ownership

- [x] 2.1 In `_ClockPanelState`, add independent latest-generation tracking for selected-date event requests and month-indicator requests.
- [x] 2.2 Update `_fetchEvents` so only the latest request matching `_selectedDate` may update `_fetchResult`, `_loading`, polling status, or trigger indicator refresh; preserve current status rendering and ready-result behavior.
- [x] 2.3 Update `_refreshIndicators` so only the latest request matching `_calendarMonth` may replace `_indicators`; preserve parallel fetching, date keys, unique sorted colors, and the three-color limit.
- [x] 2.4 Change `_updatePollTimer` to read `_selectedDate` at tick time while preserving its five-second create-once cadence, status-based cancellation, and `dispose` cleanup.

## 3. Validation and Scope Guard

- [x] 3.1 Run the focused clock/calendar widget tests and confirm out-of-order event, timer, month, and disposal scenarios pass deterministically.
- [x] 3.2 Run `dart format --output=none --set-exit-if-changed lib/widgets/panels/clock_panel.dart test` and `flutter analyze`.
- [x] 3.3 Run the complete `flutter test` suite and confirm existing calendar, panel rendering, authorization-status presentation, and unrelated UI tests remain green.
- [x] 3.4 Review the diff and confirm no changes to `native/**`, `lib/rust_gen/**`, manifests, lockfiles, calendar status strings, polling cadence, OAuth/cache behavior, persisted formats, dependencies, or unrelated panels.
