## Context

`native/alice_platform/src/runtime.rs::build_snapshot` uses `CachedMprisMediaProvider`, backed by the event-maintained `MprisCache`. `native/alice_platform/src/mpris.rs` still defines the older `MprisMediaProvider`; its private `read_from_connection` calls private `read_player_snapshot`, and an exhaustive repository search found no other caller. The crate builds only as a `staticlib`; FRB exports functions from `api.rs`, not these Rust types.

## Goals / Non-Goals

**Goals:**
- Leave one production media snapshot path: `MprisCache` → `CachedMprisMediaProvider` → `MediaSnapshot`.
- Remove only unreachable blocking snapshot-read code.
- Preserve cached projection and control fallback behavior.

**Non-Goals:**
- Changing `MediaSnapshot`, FRB APIs, player selection, event subscriptions, timing, or formatting.
- Removing `BlockingConnection`, `BlockingProxy`, `list_player_names`, or fresh discovery used by media controls.
- Editing `runtime.rs`, generated bindings, Dart, manifests, or unrelated tests unless verification exposes an unexpected live reference.

## Decisions

### Delete the legacy provider as one coherent unit

Remove `MprisMediaProvider`, `MprisMediaProvider::new`, `MprisMediaProvider::read_from_connection`, its `MediaProvider` implementation, and `read_player_snapshot`. Do not generalize or merge them into the cache path: the cache path already supplies the required behavior.

Alternative: retain the provider as a fallback. Rejected because no call site selects it and normal snapshots are contractually cache-backed.

### Preserve blocking control discovery

Keep `with_control_target`, `cached_control_target`, `choose_control_target`, and `list_player_names`. These implement the required fallback when a cached control target disappears and are not duplicate snapshot assembly.

### Verification boundary

Search the full repository excluding generated/build/archive content before deletion. If a dynamic registration or FFI export is discovered, stop; do not silently remove it. Current inspection found none.

## Risks / Trade-offs

- **Hidden external Rust consumer** → The crate emits only `staticlib` and the removed symbols are not C ABI/FRB exports; still run repository-wide symbol searches.
- **Deleting shared helpers used by controls** → Remove only the named provider/read helper and let compilation prove imports remain valid.

## Migration Plan

Delete the unreachable unit, compile/test, and revert the deletion if an unexpected consumer appears. No data, rollout, or generated-code migration is required.

## Open Questions

None. The verified runtime architecture determines the least-invasive shape.
