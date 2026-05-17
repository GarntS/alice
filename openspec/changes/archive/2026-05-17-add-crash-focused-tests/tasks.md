## 1. Test Infrastructure

- [x] 1.1 Create the Flutter `test/` directory and shared test helpers for synthetic `AliceConfig`, `BarSnapshot`, tray items, notifications, media, and workspace snapshots.
- [x] 1.2 Add a reusable widget pump helper that wraps Alice widgets in a bounded `MaterialApp`/theme context without native services.
- [x] 1.3 Verify `flutter test` discovers the new suite and does not require Wayland, GTK layer-shell, D-Bus, Google Calendar, or network access.

## 2. Flutter Boundary Tests

- [x] 2.1 Add a top-bar mixed snapshot widget test covering workspaces, media, metrics, network label behavior, tray overflow, unread notifications, and power controls.
- [x] 2.2 Add panel rendering tests for media, tray overflow, notifications, and power panels with empty and populated edge-case data.
- [x] 2.3 Add focused calendar widget or clock-panel-safe rendering coverage that avoids real calendar network calls.
- [x] 2.4 Add panel controller transition tests for same-panel toggle, different-panel replacement, anchor tracking, and idempotent close.
- [x] 2.5 Add `AlicePlatform.showPanel` / `hidePanel` method-channel tests asserting the native payload fields.

## 3. Rust Test Seams and Coverage

- [x] 3.1 Replace or adjust the environment-coupled `load_native_config_succeeds` test so Rust tests do not assert against the developer's real Alice config.
- [x] 3.2 Add hermetic config tests using explicit temporary paths and in-memory YAML for default creation, existing-file parsing, and fallback behavior.
- [x] 3.3 Extract a minimal snapshot aggregation seam from `runtime.rs` that can accept fake providers while preserving the production snapshot stream behavior.
- [x] 3.4 Add Rust tests proving snapshot aggregation succeeds with complete fake provider data.
- [x] 3.5 Add Rust tests proving independent provider failures produce the implemented fallback values without panic.

## 4. Verification

- [x] 4.1 Run `flutter test` and fix any test-only seams or widget harness issues until it passes.
- [x] 4.2 Run `cargo test --manifest-path native/Cargo.toml` and fix hermeticity or snapshot aggregation issues until it passes.
- [x] 4.3 Review the new tests for over-scoping; split or simplify any test that makes failures hard to localize.
