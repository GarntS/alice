## Why

Panel variants are repeated across independent wire-id mappings, six notifier fields, six getters, and notifier switches. Centralizing panel identity and enum-keyed notifier storage removes drift-prone bookkeeping while retaining the granular rebuild behavior that the UI depends on.

## What Changes

- Give every `AlicePanel` one canonical native wire id while retaining `alicePanelFromId` as the compatible parsing API.
- Replace per-panel notifier fields and notifier-selection switches with one complete `AlicePanel`-keyed notifier registry.
- Keep the six existing named open-state getters as compatibility façades over the registry.
- Make `AliceApp` use the panel's canonical wire id instead of maintaining a reverse `_panelId` switch.
- Preserve single-open-panel semantics, anchors, exact listener notifications, native payloads, and granular top-bar rebuild isolation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-controller`: Require canonical, round-trippable native panel identities while preserving granular per-panel listenable behavior.

## Impact

- Primary code: `lib/panel_controller.dart` (`AlicePanel`, `alicePanelFromId`, `PanelController`) and `lib/app.dart` (`_syncPanelState`, removal of `_panelId`).
- Verified consumers: `lib/alice_platform.dart`, `lib/widgets/top_bar.dart`, `lib/widgets/panels/panel_sizes.dart`, and `lib/widgets/panels/panel_host.dart` retain their existing APIs and behavior.
- Tests: `test/panel_controller_test.dart`, `test/rebuild_isolation_test.dart`, `test/panel_command_view_map_test.dart`, and `test/alice_platform_channel_test.dart` as needed.
- No panel-size ownership changes, native/C++ changes, generated binding changes, wire-id changes, public API removals, dependencies, or persisted-format changes.
