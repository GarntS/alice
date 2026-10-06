## 1. Configuration

- [x] 1.1 Add nested notification sound configuration with enabled/bundled/50 defaults, optional absolute file path, and integer volume validation; isolate malformed sound settings from notification delivery.
- [x] 1.2 Add configuration tests for omitted sections/fields, explicit overrides, disabled/zero-volume settings, invalid volume/types, and empty/relative/URL/home-shorthand paths.
- [x] 1.3 Update exposed configuration representations and regenerate bridge bindings if required; verify existing configuration consumers remain compatible.

## 2. Asset and playback worker

- [x] 2.1 Create a short, gentle original WAV chime under assets/sounds, record provenance/licensing, and embed it in the native binary.
- [x] 2.2 Add the native audio dependency and required Nix development/build dependencies; verify WAV decoding and Linux output compilation.
- [x] 2.3 Implement an owned audio worker with bounded nonblocking requests, serialized playback, configured gain, custom-file decoding, shutdown cleanup, and rate-limited failure diagnostics without default fallback.
- [x] 2.4 Add fake-backend tests for volume application, default/custom selection, initialization/file/decoding failures, queue saturation, and worker cleanup without requiring audio hardware.

## 3. Notification integration

- [x] 3.1 Wire shared sound requests into successful D-Bus admission; distinguish real replacements from missing replacement targets and honor boolean suppress-sound hints.
- [x] 3.2 Wire internal calendar notification admission into the same policy and initialize audio independently of notification delivery.
- [x] 3.3 Test new external/internal receipt, silent replacements, missing replacement targets, sender suppression, ignored sender sound overrides, disabled/zero-volume audio, and popup-independent playback.
- [x] 3.4 Verify snapshot refreshes, read changes, dismissals, panel opening, and popup visibility changes never request playback; verify audio failures preserve canonical notification storage and triggers.

## 4. Documentation and validation

- [x] 4.1 Update default_config.yaml and README with sound defaults, an optional absolute-file example, supported formats, volume range, replacement silence, and failure behavior.
- [x] 4.2 Run native tests/lints and relevant Flutter configuration/notification regressions, using nix develop where required.
- [x] 4.3 Build the installed package and manually verify bundled playback outside the source checkout, custom-file playback, 50-percent gain, sender suppression, silent replacements, and unavailable audio output behavior.
