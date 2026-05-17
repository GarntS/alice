## 1. MPRIS Cache Model

- [x] 1.1 Define an internal cached MPRIS player/media state model with bus name, metadata, playback status, track id, base position, observed timestamp, and length.
- [x] 1.2 Add projection logic that converts cached state into `MediaSnapshot`, preserving current player selection rules and formatting behavior.
- [x] 1.3 Add unit tests for projection, including playing position advancement, paused position stability, empty-title filtering, and playing-player preference.

## 2. MPRIS Watcher

- [x] 2.1 Add an async MPRIS runtime service that connects to the session bus once and performs initial player discovery.
- [x] 2.2 Watch `NameOwnerChanged` for `org.mpris.MediaPlayer2.*` names and update the cache when players appear or disappear.
- [x] 2.3 Watch per-player `PropertiesChanged` events for `org.mpris.MediaPlayer2.Player` and update cached metadata, playback status, and position fields.
- [x] 2.4 Emit snapshot triggers when player lifecycle or property changes alter projected media state.
- [x] 2.5 Ensure watcher failures are logged and do not crash the snapshot stream.

## 3. Snapshot Runtime Integration

- [x] 3.1 Create the MPRIS cache before the snapshot loop and pass it to both the watcher and cached media provider.
- [x] 3.2 Replace production snapshot media reads with the cached provider so unrelated triggers do not perform MPRIS rediscovery/property reads.
- [x] 3.3 Add a media-position refresh trigger that emits while the selected cached player is playing.
- [x] 3.4 Preserve the existing 50 ms debounce and provider failure fallback behavior.

## 4. Media Controls

- [x] 4.1 Update media control target selection to prefer the cached selected/displayed player when available.
- [x] 4.2 Fall back to the existing fresh discovery target selection when the cached player is missing or unusable.
- [x] 4.3 Preserve existing public FRB APIs and Flutter-facing behavior for previous, play/pause, next, and seek.

## 5. Verification

- [x] 5.1 Add or update Rust tests covering cached media provider behavior without live D-Bus dependencies.
- [x] 5.2 Run `cargo test --manifest-path native/Cargo.toml` and fix regressions.
- [x] 5.3 Run relevant Flutter tests if public snapshot behavior or generated bindings are affected.
- [x] 5.4 Run `openspec validate fix-mpris-event-cache --strict` and fix any proposal/spec/task issues.
