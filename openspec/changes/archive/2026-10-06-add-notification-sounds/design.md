## Context

See proposal.md for motivation and specs/notification-sounds/spec.md for the behavior contract. Rust owns notification admission through D-Bus `notify` and internal calendar injection. Flutter consumes periodic/event-driven snapshots, making UI-driven audio susceptible to duplicate playback. The native crate currently has no audio playback dependency. Default YAML is embedded at compile time, providing an established pattern for bundling resources.

## Goals / Non-Goals

**Goals:** Keep sound policy native, cover both admission paths, isolate audio failures, and make installed defaults independent of deployment paths.

**Non-Goals:** Per-application sound rules, sender-selected sound assets, sound-theme lookup, UI configuration controls, system master-volume changes, and notification replacement sounds.

## Decisions

### Configuration belongs under notifications.sound

Use `enable: true`, optional `file`, and integer `volume: 50`. Treat missing file as a bundled resource, not a magic string or deployed filesystem path. Validate custom paths as absolute without expanding `~` or evaluating shell expressions. Invalid sound-specific values disable sound with a diagnostic rather than rejecting otherwise usable notification configuration. Keep this validation separate from file existence checks so transient filesystem failures remain playback errors.

Alternative: flatten three keys into the notification section. A nested group better separates audio from existing popup controls. Preserve existing omitted-field compatibility and update generated bridge types if the exposed native notification configuration changes.

### Trigger at admission, not projection

Determine whether D-Bus receipt actually replaces a retained record and pass new-notification eligibility into a shared sound request helper. Invoke the helper only after successful admission. Use the same helper for internal notifications. Parse the boolean `suppress-sound` hint before requesting external playback; ignore sender sound-file/name hints. Sound does not depend on popup configuration or urgency.

Alternative: detect new IDs in Flutter snapshots. Rejected because coalesced snapshots can miss arrivals and multi-view consumers can duplicate side effects.

### Embed an original WAV chime

Add a short, gentle PCM WAV asset under `assets/sounds/` and embed its bytes in the Rust binary. Record provenance/licensing alongside the asset. This avoids installation-path discovery and works in source builds and Nix packages alike. Do not copy a default file into the user configuration directory or silently replace a broken custom sound with it.

Alternative: install a shared data file and resolve its location at runtime. Embedding is simpler for this small, single asset.

### Own audio in a dedicated worker

Use a native Rust audio playback backend, with rodio as the preferred implementation, and a dedicated worker owning the output stream for its lifetime. Decode bundled WAV bytes or configured local files there and apply volume as gain `volume / 100`; do not change system mixer settings. Require WAV support and document any additional enabled formats rather than implying arbitrary file support.

Use a bounded, nonblocking request queue so D-Bus receipt and calendar workers never wait for decoding or playback. Avoid an unbounded backlog of sounds: discard requests on saturation, with a rate-limited diagnostic. Requests are best-effort under resource exhaustion. Serialize playback in the worker rather than spawning a thread/process per notification. Ensure shutdown releases the stream and worker. Audio backend initialization failure disables playback but never disables the notification server.

Alternative: shell out to an audio player. Rejected because executable discovery, command-line volume semantics, and Nix runtime wrapping would make behavior less predictable. Confirm the selected rodio version's Linux output requirements and update Nix development/build dependencies accordingly.

### Test policy independently from devices

Separate receipt eligibility and configuration validation from the real backend through an injectable playback-request interface. Test both admission paths with a fake recorder and use a failing backend to verify delivery isolation. Do not require audio hardware in automated tests. Perform installed-package playback validation separately.

## Risks / Trade-offs

- [Linux backend libraries may require Nix build/link changes] → Verify in `nix develop` and package builds; explicitly include required dependencies.
- [Notification bursts create noisy or delayed sounds] → Keep the asset short and bound pending requests; replacements are silent.
- [Repeated custom-file failures flood logs] → Rate-limit repeated diagnostics without producing notifications.
- [A long custom file occupies the worker] → Keep requests bounded and preserve notification delivery; arbitrary custom durations are not guaranteed to produce timely subsequent sounds.
- [Configuration decoding rejects a malformed sound subsection before local validation] → Make sound-specific parsing tolerant enough to diagnose and disable audio without losing the rest of the configuration.

## Migration Plan

Existing configurations need no edits and acquire the documented defaults. Update first-run YAML and README with a commented absolute custom-file example and supported formats. Validate unit tests, existing notification regressions, and packaged asset availability. Rollback removes the audio integration and keys while leaving notification storage and popup behavior unchanged.
