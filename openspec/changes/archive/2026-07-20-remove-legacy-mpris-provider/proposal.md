## Why

The event-driven MPRIS cache is the sole production source for media snapshots, but `mpris.rs` still carries the superseded blocking snapshot provider and its duplicate D-Bus read path. Removing that unreachable strategy makes the implemented architecture match the current MPRIS contract and reduces future maintenance ambiguity.

## What Changes

- Remove `MprisMediaProvider`, its constructor and `MediaProvider` implementation, its blocking `read_from_connection` path, and `read_player_snapshot`.
- Keep `CachedMprisMediaProvider`, `MprisCache`, event subscriptions, projection, and all blocking media-control fallback behavior unchanged.
- Add mechanically checkable guards against reintroducing D-Bus rediscovery during snapshot assembly.
- Preserve all FRB APIs and `MediaSnapshot` fields.

## Capabilities

### New Capabilities

### Modified Capabilities
- `mpris-media`: Clarify that normal media snapshot assembly has one cache-backed acquisition path while fresh D-Bus discovery remains available only for control fallback.

## Impact

- Affected implementation: `native/alice_platform/src/mpris.rs`.
- Verified runtime call site: `native/alice_platform/src/runtime.rs::build_snapshot` already constructs `CachedMprisMediaProvider`; no runtime edit is expected.
- Tests: MPRIS cache/projection tests and the complete Rust suite.
- APIs and dependencies: no public FRB/C shape or Cargo dependency changes.
