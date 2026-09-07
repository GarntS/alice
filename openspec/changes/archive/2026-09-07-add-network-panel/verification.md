# Verification

- `nix develop --command cargo clippy --manifest-path native/Cargo.toml --workspace --all-targets -- -D warnings`: passed.
- `nix develop --command cargo test --manifest-path native/Cargo.toml --workspace`: passed (148 platform tests, 4 layer-shell tests).
- `nix develop --command flutter test --reporter expanded`: passed (92 tests), including the follow-up spacing, shared-title, card-icon, typography, compact row order, long-value constraints, and empty-WireGuard regressions.
- Changed Dart files pass `dart format --output=none --set-exit-if-changed`.
- Bindings regenerated with `flutter_rust_bridge_codegen generate`, followed by `cargo fmt --manifest-path native/Cargo.toml --all`; hashes match the checked implementation. The final formatting step normalizes Rust 2024 import ordering used by this workspace.
- `openspec validate add-network-panel --strict`: passed.

The Netlink tests use fake streams, sessions, buffers, and observations, not live interfaces, Wi-Fi/WireGuard devices, D-Bus, network commands, or elevated privileges. They cover capped/denied receive-buffer requests, successful versus incomplete/interrupted multipart dumps, overrun/panic/termination recovery, timeout, delayed retry, notification reconciliation, periodic refresh, read-only cached-BSS requests, SSID bounds/escaping, icon precedence, address selection, and unavailable observations. Kernel/driver permission failures remain explicit unavailable states; no live-driver access guarantee is implied.

The obsolete runtime watcher was removed as part of integration, resolving its prior Clippy failure. Four existing internal unit structs are annotated as opaque because FRB 2.12 otherwise panics while inspecting them during generation; no new provider APIs are exposed to Flutter.
