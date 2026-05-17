## Context

The snapshot runtime currently rebuilds a full `BarSnapshot` whenever any trigger arrives. `MprisMediaProvider` is stateless: every `read_media()` call opens/uses a session bus connection, lists all D-Bus names, filters `org.mpris.MediaPlayer2.*`, and reads each candidate player's properties. There is no explicit MPRIS trigger source in `runtime.rs`.

In practice, media stays fresh because the 1 second stats timer continually triggers full snapshot rebuilds. This creates accidental coupling between media freshness and metric polling, and it makes each rebuild do more D-Bus work than necessary.

MPRIS has two different update shapes:

- Discrete state changes: player appears/disappears, metadata changes, playback status changes, seek/position jumps.
- Continuous display: the elapsed position label advances while playback is active.

The fix should make both update shapes explicit without requiring a full MPRIS rediscovery/property poll on every unrelated snapshot trigger.

## Goals / Non-Goals

**Goals:**
- Add an explicit MPRIS runtime service that maintains cached media state.
- Subscribe to MPRIS player lifecycle changes and player property changes.
- Make snapshot assembly read cached MPRIS state cheaply.
- Update the displayed elapsed position from cached base position plus monotonic elapsed time while playing.
- Add an explicit media-position trigger while playback is active.
- Preserve existing public Dart/Rust media APIs and UI behavior.

**Non-Goals:**
- Replacing the existing public `MediaSnapshot` shape.
- Adding multi-player UI selection.
- Removing the global 1 second metrics trigger.
- Guaranteeing perfect position synchronization for players that do not expose reliable `Position` values.
- Changing MPRIS method semantics for previous/play-pause/next/seek beyond target selection robustness.

## Decisions

### Stateful MPRIS cache owned by the runtime

Introduce a shared MPRIS cache, owned by the snapshot runtime and passed to both the MPRIS watcher and a cached media provider.

Conceptually:

```text
MPRIS D-Bus events ──▶ cache manager ──▶ Arc/RwLock cache ──▶ snapshot provider
                                  └──▶ Trigger::Event
```

The cache should store an internal representation rather than only a public `MediaSnapshot`, because the public snapshot contains formatted labels and an instantaneous position. The internal model needs enough information to project a fresh `MediaSnapshot` at read time:

- player bus name
- metadata fields
- playback state
- track id when available
- base position in microseconds
- monotonic timestamp for when that position was observed
- length in microseconds

Alternative considered: store `MediaSnapshot` directly and update it on every tick. That keeps the model simple but turns the cache into another polling loop and makes position derivation harder to test.

### Event-driven MPRIS watcher

Add an async MPRIS watcher that connects once to the session bus, performs initial discovery, then watches:

- `org.freedesktop.DBus.NameOwnerChanged` for names with the `org.mpris.MediaPlayer2.` prefix.
- `org.freedesktop.DBus.Properties.PropertiesChanged` for player properties at `/org/mpris/MediaPlayer2` on `org.mpris.MediaPlayer2.Player`.

On player appearance, the watcher reads initial player state and inserts/updates the cache. On disappearance, it removes the player. On relevant property changes, it updates only the changed cached fields where possible; if a change is incomplete or ambiguous, it may reread that player rather than rediscovering all players.

Alternative considered: add only a trigger and keep the existing stateless provider. That would fix freshness semantics but still perform full D-Bus rediscovery/read work on every snapshot build.

### Cached provider projection

Replace production use of the stateless provider with a cached provider. Snapshot assembly should call `read_media()` on a provider that clones/projects the current cache state without D-Bus I/O.

Player selection should preserve current behavior: prefer a currently playing player; otherwise fall back to the first player with usable metadata.

Projection computes:

```text
if playing:
  display_position = base_position + elapsed_since(base_observed_at)
else:
  display_position = base_position
```

The projected position should be non-negative and may be clamped to track length when length is known.

### Explicit media position trigger while playing

Add a media-position trigger source that emits snapshot triggers while cached selected media is playing. This trigger exists to repaint the elapsed position label and should not perform D-Bus reads.

The existing 1 second stats timer may still cause snapshots at the same cadence, but media correctness should not depend on that timer.

Alternative considered: rely on Flutter to animate/derive position locally. That would avoid Rust position ticks but would require changing the public data contract and duplicating timing behavior in the UI.

### Control target selection

Media controls should prefer the cached selected/displayed player when available so the controls act on what Alice is showing. If that cached target is unavailable or the D-Bus call fails because the player vanished, controls should fall back to current fresh discovery behavior.

This hybrid approach preserves robustness while making controls consistent with the cached UI.

## Risks / Trade-offs

- **D-Bus signal matching may miss non-conforming players** → Perform initial discovery and use fresh fallback for controls; keep provider failure tolerance.
- **Position drift for long-running playback** → Refresh base position on `PropertiesChanged`/seek events when available; clamp to known length; accept small drift as preferable to polling MPRIS every second.
- **Concurrency bugs in shared cache** → Keep cache mutation centralized in the watcher and expose a small read-only provider surface for snapshot assembly.
- **Duplicate snapshot ticks while stats and media both run at 1 second** → Existing 50 ms debounce collapses bursts; media tick can be conditional on active playback.
- **Player disappears during a control action** → Try cached target first, then fall back to fresh discovery or return the existing failure behavior.
