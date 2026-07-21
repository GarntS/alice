## 1. Calendar Grid Coverage

- [x] 1.1 Extend focused `AliceCalendar` widget tests to verify a representative month renders a Sunday-first six-by-seven sequence including expected preceding/following month boundary dates.
- [x] 1.2 Add navigation assertions that previous and next controls move exactly one month and invoke `onMonthChanged` exactly once per action while date selection and indicator placement remain unchanged.
- [x] 1.3 Add coverage that the today decoration corresponds to the current local date at render time and remains distinct from selected-date decoration under the existing rules.

## 2. Derived Grid Implementation

- [x] 2.1 Remove `_CalendarDay` and change `_buildMonthRows` and `_DayCell` to use `DateTime` cells directly while preserving `_dateKey` indicator lookup and date comparisons.
- [x] 2.2 Remove stored `_rows`; derive the 42 consecutive dates and six rows from `_displayedMonth` in `build`, and simplify previous/next handlers to mutate only `_displayedMonth` before invoking the callback.
- [x] 2.3 Remove stored `_today`; derive the date-only local current day in `build` and preserve selected/today/current-month styling behavior.

## 3. Validation and Scope Guard

- [x] 3.1 Run the focused calendar and panel rendering tests and confirm grid boundaries, navigation, selection, today highlighting, and indicators pass.
- [x] 3.2 Verify `rg -n "_CalendarDay|late DateTime _today|late List<List<.*>> _rows" lib/widgets/panels/clock_panel.dart` returns no obsolete derived-state declarations.
- [x] 3.3 Run `dart format --output=none --set-exit-if-changed lib/widgets/panels/clock_panel.dart test` followed by `flutter analyze` and the complete `flutter test` suite.
- [x] 3.4 Review the diff and confirm `ClockPanel` fetch/polling logic, Google Calendar bridge behavior, native/generated files, public constructors, dependencies, styling, dimensions, and unrelated panels are unchanged; if `stabilize-clock-async-state` is already applied, retain its async ownership checks and fetch seam.
