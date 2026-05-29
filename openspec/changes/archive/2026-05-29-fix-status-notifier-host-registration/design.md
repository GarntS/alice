## Context

Alice implements a StatusNotifierWatcher service in `native/alice_platform/src/tray.rs` and owns both KDE and freedesktop watcher bus names. The watcher accepts item and host registration calls, and the snapshot runtime reads registered items into tray snapshots.

Live debugging showed Alice owned the watcher names but reported `IsStatusNotifierHostRegistered = false` and `RegisteredStatusNotifierItems = []`. After manually calling `RegisterStatusNotifierHost`, restarting TIDAL Hi-Fi caused its tray item to register and render. This indicates some tray clients gate item publication on host registration state and/or host registration signals.

## Goals / Non-Goals

**Goals:**
- Advertise Alice as an active StatusNotifier host during watcher startup.
- Notify tray clients that a host is available using the standard watcher signal.
- Notify observers when new tray items register.
- Keep snapshot refresh behavior and tray UI behavior unchanged except that clients now register reliably.

**Non-Goals:**
- Add legacy XEmbed tray support.
- Replace Alice's in-process watcher with an external watcher dependency.
- Change Flutter tray rendering, tray overflow behavior, or user-facing configuration.
- Implement full menu rendering beyond existing tray action routing.

## Decisions

### Alice self-registers the host at watcher startup

When the watcher service starts and successfully owns the watcher bus names, it should set the shared watcher state's `host_registered` flag to `true` and emit `StatusNotifierHostRegistered` on the watcher interface(s). This models Alice's bar as the tray host rather than waiting for an external caller.

Alternative considered: require Flutter or another process to call `RegisterStatusNotifierHost`. That keeps the watcher generic, but it reproduces the current failure mode when no caller performs the registration. Alice already owns both watcher and host roles, so startup self-registration is simpler and more robust.

### Emit registration signals as part of watcher state transitions

When `RegisterStatusNotifierItem` adds a new canonical item id, the watcher should emit `StatusNotifierItemRegistered` in addition to triggering a snapshot rebuild. When host registration transitions from false to true, it should emit `StatusNotifierHostRegistered`.

Alternative considered: rely on clients polling watcher properties. The TIDAL experiment suggests some clients need proper lifecycle behavior, and the SNI watcher contract includes these signals.

### Keep shared watcher state as the source of truth

The existing `WatcherState` remains the source for registered items and host status. Signal emission should be layered around successful state transitions without duplicating item storage.

Alternative considered: move watcher state into zbus object instances. That would make signal emission more local, but Alice currently exposes KDE and freedesktop watcher interfaces over shared state, and keeping that model minimizes churn.

## Risks / Trade-offs

- **Risk:** Emitting signals before bus names are owned may be missed or ignored. → Emit after object registration and name acquisition, and keep the property state set so late clients can still poll.
- **Risk:** Double host registration calls could produce duplicate signals. → Emit only on false-to-true state transitions.
- **Risk:** Item registration signal emission may need to occur on both KDE and freedesktop interfaces. → Treat both watcher interfaces consistently so clients observing either namespace receive expected lifecycle events.
- **Risk:** Existing tests may not exercise zbus signal emission directly. → Add unit coverage for state transition helpers where possible and use integration/manual validation for live D-Bus behavior if direct signal tests are impractical.
