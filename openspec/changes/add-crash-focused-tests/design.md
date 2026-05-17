## Context

Alice is split across Flutter UI, Rust native providers/runtime, and C++ GTK/layer-shell window management. The existing Rust unit tests cover several parsing and provider helpers, but there is no Flutter test directory, and at least one Rust test reads the real user configuration. The crashes being investigated are likely to occur where real-world state crosses boundaries: snapshots into widgets, panel state into native show/hide calls, provider failures into snapshot fallbacks, and local configuration into defaults.

The test suite should therefore add a few broad but debuggable tests around those seams, not a large collection of narrow implementation tests.

## Goals / Non-Goals

**Goals:**
- Make `flutter test` run a useful suite instead of failing because `test/` is absent.
- Add high-signal Flutter tests for rendering representative `BarSnapshot` data through top-bar and panel widgets.
- Add tests for panel controller semantics and method-channel payload construction.
- Make Rust config tests hermetic and independent of the developer's actual `$XDG_CONFIG_HOME`.
- Add a Rust snapshot assembly test seam that verifies provider failure fallbacks without touching Sway, D-Bus, procfs, network state, or Wayland.

**Non-Goals:**
- Do not add a full end-to-end Wayland/GTK/layer-shell integration test.
- Do not require a live Sway session, D-Bus session, Google Calendar account, network interface changes, or real StatusNotifier items.
- Do not pursue exhaustive widget golden testing or screenshot comparison.
- Do not change runtime user-facing behavior except for small refactors needed to make existing behavior testable.

## Decisions

### Prefer boundary tests over quantity

The first pass will add a small number of tests that each exercise a complete boundary:

- `TopBar` with a rich mixed snapshot.
- Panel widgets with edge-case snapshots and bounded layout constraints.
- Panel controller state transitions plus `AlicePlatform.showPanel` / `hidePanel` method-channel payloads.
- Rust config load/create behavior with temporary paths.
- Rust snapshot aggregation with fake providers that fail independently.

Alternative considered: adding many per-widget unit tests. That would improve line coverage but would be less useful for crash triage because most day-to-day crashes are likely to involve composition, layout constraints, generated FRB data shapes, or platform seams.

### Keep tests hermetic

New tests must not read or mutate the developer's actual config, depend on live desktop services, or require network access. Rust tests should use temporary directories and fake providers. Flutter tests should construct generated snapshot/config values directly.

Alternative considered: running integration tests against a live desktop session. That may be useful later, but it would be flaky and hard to debug as a first crash-focused suite.

### Add narrow test seams where needed

Some desired tests are blocked by private or concrete implementations:

- Snapshot assembly currently instantiates concrete providers directly inside `runtime.rs`.
- Tray icon stabilization is private inside `AlicePlatform`.
- `ClockPanel` directly calls generated `fetchCalendarEvents`.

The implementation should add the smallest reasonable seams needed for tests. For example, extract snapshot aggregation into a function that accepts provider trait objects or generic provider values, while keeping the production `build_snapshot()` behavior unchanged.

Alternative considered: testing only public runtime streams. That would require real system services and would make failures much harder to isolate.

### Avoid testing generated FRB internals

Flutter tests may construct generated data classes from `lib/rust_gen/state.dart`, but should not assert on generated serialization implementation. The tests should target Alice-owned widgets/adapters and Rust-owned aggregation logic.

## Risks / Trade-offs

- Test seams could accidentally over-abstract production code → Keep refactors minimal and production call paths unchanged.
- Widget tests can become brittle if they assert too much visual detail → Assert presence, absence, callbacks, and no exceptions rather than exact layout pixels.
- Panel tests could over-scope into full app multi-view behavior → Test `PanelController`, `AlicePlatform` method-channel payloads, and individual panel widgets separately.
- Clock panel calendar behavior is hard to test without a seam → Start by testing `AliceCalendar` and non-network panel rendering; only add a calendar fetch seam if needed for stable panel coverage.
- Existing environment-coupled Rust tests may keep failing → Replace or adjust those tests to use explicit temporary config paths.
