## Why

Alice currently delivers notifications visually but provides no audible cue. Configurable notification sounds let users notice new notifications while controlling the sound and its volume.

## What Changes

- Ship a short, gentle notification chime and use it when no custom file is configured.
- Add `notifications.sound.enable`, optional `notifications.sound.file`, and `notifications.sound.volume` to `config.yaml`, defaulting to enabled, the bundled asset, and 50 percent.
- Require custom files to be absolute local paths.
- Sound new external and internal notifications, independently of popup visibility; keep replacements silent and honor external `suppress-sound` hints.
- Log custom-file or playback failures without falling back to the bundled sound or affecting notification delivery.

## Capabilities

### New Capabilities

- `notification-sounds`: Notification receipt sound policy, bundled asset, configurable playback, and failure isolation.

### Modified Capabilities

None. The new capability owns its additional configuration requirements; existing notification storage and popup requirements remain unchanged.

## Impact

- Native configuration parsing/defaults and notification receipt paths in `native/alice_platform/src/config.rs`, `notifications.rs`, and `runtime.rs`.
- Native audio playback dependency and associated Nix/build packaging requirements.
- Bundled sound asset, default YAML, README configuration documentation, and tests.
- Any bridge-generated configuration representations affected by extending native configuration types.
