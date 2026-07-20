## 1. Confirm Removal Boundary

- [x] 1.1 Search non-generated, non-build, non-archive repository content for `MprisMediaProvider` and `read_player_snapshot`; confirm their only live references are the legacy unit in `native/alice_platform/src/mpris.rs`.
- [x] 1.2 Confirm `native/alice_platform/src/runtime.rs::build_snapshot` still constructs `CachedMprisMediaProvider` and that FRB/C exports do not name the legacy symbols.

## 2. Remove Legacy Snapshot Acquisition

- [x] 2.1 Delete `MprisMediaProvider`, its constructor/private reader, and its `MediaProvider` implementation from `native/alice_platform/src/mpris.rs`.
- [x] 2.2 Delete private `read_player_snapshot` while preserving `with_control_target`, `list_player_names`, `choose_control_target`, blocking control proxies, cache projection, and formatting helpers.
- [x] 2.3 Remove only imports made unused by those deletions; do not edit runtime, generated bindings, Dart, manifests, or public snapshot/API shapes.

## 3. Verify Preservation

- [x] 3.1 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform mpris::tests`.
- [x] 3.2 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform` and require all tests to pass.
- [x] 3.3 Search active repository content and require zero occurrences of `MprisMediaProvider` and `read_player_snapshot`, while confirming cached provider and fresh control fallback symbols remain.
- [x] 3.4 Run `openspec validate remove-legacy-mpris-provider --strict`.
