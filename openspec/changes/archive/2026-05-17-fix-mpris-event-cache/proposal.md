## Why

Alice currently keeps MPRIS media fresh by rebuilding the whole snapshot on unrelated triggers, especially the 1 second stats timer. This makes media updates accidental, causes repeated D-Bus rediscovery/property reads, and contradicts the intended event-driven MPRIS design.

## What Changes

- Add an explicit MPRIS runtime service that watches player lifecycle and player property changes over the session bus.
- Maintain an in-process cached media state that snapshot assembly can read cheaply without rediscovering all MPRIS players on every trigger.
- Trigger snapshot rebuilds when MPRIS players appear, disappear, or emit relevant property changes.
- Derive the displayed playback position from cached base position plus elapsed monotonic time while the selected player is playing.
- Add an explicit media position refresh trigger while playback is active, so elapsed labels are not coupled to system metric polling.
- Keep MPRIS control actions user-facing compatible; prefer controlling the displayed cached player when possible, with fallback to fresh discovery if needed.

## Capabilities

### New Capabilities

### Modified Capabilities
- `mpris-media`: Add event-driven MPRIS cache, player lifecycle/property subscriptions, cached snapshot reads, and derived position behavior.
- `snapshot-runtime`: Add MPRIS event and media-position triggers to the snapshot runtime trigger contract.

## Impact

- Affected Rust code: `native/alice_platform/src/runtime.rs`, `native/alice_platform/src/mpris.rs`, possibly provider wiring and tests around snapshot assembly.
- Affected specs: `openspec/specs/mpris-media/spec.md`, `openspec/specs/snapshot-runtime/spec.md`.
- Affected runtime behavior: fewer MPRIS D-Bus calls during normal snapshot builds, explicit media updates on D-Bus events, and position labels that continue updating while playback is active.
- Dependencies: may use existing async `zbus` support already available through the current `zbus` dependency; avoid adding a new bus library unless required.
