## Why

Alice currently has meaningful Rust unit coverage but no Flutter test suite, and one Rust test depends on the developer's real configuration. That leaves day-to-day crash investigation without stable, repeatable coverage at the boundaries most likely to fail: snapshot-shaped UI rendering, panel coordination, config loading, and provider fallback behavior.

## What Changes

- Add a small set of high-signal tests focused on crash-prone integration seams rather than broad low-value coverage.
- Introduce Flutter tests for top-bar rendering, panel rendering, panel controller behavior, and method-channel payloads.
- Add Rust tests for hermetic config loading and provider-failure-tolerant snapshot assembly.
- Avoid real Wayland, GTK, D-Bus, user config, and network dependencies in the new tests.
- Refactor only as needed to create test seams for snapshot assembly and tray icon stabilization.

## Capabilities

### New Capabilities
- `crash-focused-test-coverage`: Defines the project test coverage expectations for high-signal crash regression tests across Flutter and Rust boundaries.

### Modified Capabilities
- `configuration`: Configuration tests must be hermetic and must not read or assert against the developer's real `$XDG_CONFIG_HOME` configuration.
- `snapshot-runtime`: Snapshot assembly must expose a testable provider-aggregation seam so provider failure fallback behavior can be verified without real system services.

## Impact

- Affected Flutter code: `test/`, `lib/widgets/top_bar.dart`, `lib/widgets/panels/*`, `lib/panel_controller.dart`, `lib/alice_platform.dart`.
- Affected Rust code: `native/alice_platform/src/config.rs`, `native/alice_platform/src/runtime.rs`, possibly small supporting test-only seams in provider aggregation.
- Test commands affected: `flutter test` should become meaningful and pass; `cargo test --manifest-path native/Cargo.toml` should pass without depending on local user config.
- No user-facing runtime behavior changes are intended.
