## Why

Notification actions currently reach their originating application, but Alice does not ask the compositor to activate that application's window. On Sway and other wlroots compositors, actions such as Discord's “Show” or “Reply” can therefore update the application while leaving the user on an unrelated workspace.

## What Changes

- Track compositor-advertised toplevel windows through `wlr-foreign-toplevel-management-unstable-v1`, including their app IDs, titles, activation state, and lifecycle.
- Preserve the notification `desktop-entry` hint as internal origin metadata and use it to resolve a notification to an existing foreign-toplevel handle.
- When a notification action is invoked, keep emitting `ActionInvoked` and make a best-effort request to activate the matched toplevel for the compositor seat.
- Define deterministic matching and fallback behavior for absent protocol support, missing or ambiguous notification identity, stale handles, and rejected activation requests.
- Keep notification actions functional when activation is unsupported or fails; this change introduces no Sway IPC dependency for notification activation.

## Capabilities

### New Capabilities
- `foreign-toplevel-activation`: Event-driven discovery, matching, and best-effort activation of application toplevels on compositors supporting the wlroots foreign-toplevel-management protocol.

### Modified Capabilities
- `freedesktop-notifications`: Extend notification action behavior to request activation of the originating application's matched toplevel without making action delivery depend on activation success.

## Impact

- Native Wayland integration will gain a persistent foreign-toplevel tracker and activation command path using the existing `wayland-client` and `wayland-protocols-wlr` dependencies.
- Notification storage will retain internal origin metadata parsed from hints without exposing compositor handles through Flutter snapshots or FRB APIs.
- `native/alice_platform` will gain a dedicated Wayland foreign-toplevel module alongside its notification action path; `native/alice_layer_shell` will remain responsible for Alice's own layer-surface placement.
- Tests will cover identity normalization, candidate selection, lifecycle updates, unsupported compositors, activation failure, and preservation of D-Bus action behavior.
