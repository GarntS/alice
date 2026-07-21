## Context

`AliceCalendar` in `lib/widgets/panels/clock_panel.dart` stores `_displayedMonth`, `_today`, and `_rows`. `_rows` is always generated from `_displayedMonth`, and both `_prevMonth` and `_nextMonth` must update the pair together. `_today` is derived from `DateTime.now()` only in `initState`, so a long-lived panel can retain the prior day's highlight. Each cell is wrapped in `_CalendarDay`, which carries only a `DateTime` and a derived date key. The grid is always 42 cells, so derivation has fixed small cost.

## Goals / Non-Goals

**Goals:**
- Make `_displayedMonth` the only mutable grid-navigation state.
- Derive the six week rows and current date during rendering.
- Use `DateTime` directly as the cell model.
- Preserve all current visual and callback behavior while adding focused boundary coverage.

**Non-Goals:**
- Change selected-date ownership in `ClockPanel`, async event fetching, authorization polling, month-indicator fetching, date formatting, locale, styling, or panel dimensions.
- Change public `AliceCalendar` or `ClockPanel` constructor signatures.
- Add a calendar package or other dependency.

## Decisions

### Derive rows from the displayed month in build

Remove `_rows` and compute `final rows = _buildMonthRows(_displayedMonth)` in `build`. Change `_buildMonthRows` to return `List<List<DateTime>>`. It must continue to find the Sunday on or before the month's first day, generate exactly 42 consecutive dates, and partition them into six seven-day rows.

This is preferred over caching because the grid is fixed at 42 cells, month navigation is infrequent, and caching creates an invariant that all mutations must maintain.

### Derive today at render time

Remove `_today` and compute the date-only current local day in `build`. Use that value for selected/today styling exactly as today. This keeps the highlight correct on the next rebuild after midnight without introducing a midnight timer.

A timer-driven midnight rebuild is out of scope because the panel already rebuilds from clock snapshots; the purpose here is to avoid stale stored derivation, not add lifecycle machinery.

### Remove the one-field cell wrapper

Delete `_CalendarDay`. Make `_DayCell.date` a `DateTime`, update date comparisons and labels accordingly, and compute `_dateKey(date)` at indicator lookup. No wrapper-level invariant or ownership boundary is lost.

### Test behavior through the public widget

Extend `test/panels_rendering_test.dart` or add a focused calendar widget test. Verify the six-by-seven shape through the `AliceCalendar` subtree, boundary dates for representative months, one callback per previous/next action, selected-date callbacks, today styling, and indicator placement. Avoid exposing private implementation solely for tests.

## Risks / Trade-offs

- [Grid allocation occurs on each calendar rebuild] → The workload is bounded at 42 `DateTime` values and six row lists; retain this simple derivation unless profiling demonstrates a real issue.
- [Tests become coupled to incidental widget counts] → Assert public labels, callbacks, keys/decoration where stable, and scope any count assertion to the `AliceCalendar` subtree.
- [This change shares a file with async stabilization] → Keep edits confined to `_CalendarDay`, `_AliceCalendarState`, `_buildMonthRows`, and `_DayCell`; preserve any async ownership work from `stabilize-clock-async-state` if that change is applied first.
