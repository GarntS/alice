## 1. Canonical Panel Identity

- [x] 1.1 Extend `test/panel_controller_test.dart` to iterate all six `AlicePanel` values, assert their exact canonical ids (`media`, `clock`, `weather`, `trayOverflow`, `power`, `notifications`), verify enum-to-id-to-enum round trips, and preserve null for null/unknown ids.
- [x] 1.2 Convert `AlicePanel` in `lib/panel_controller.dart` to carry its canonical native wire id and make `alicePanelFromId` derive parsing from `AlicePanel.values` without a second id table.
- [x] 1.3 Remove `_AliceAppState._panelId` from `lib/app.dart` and make `_syncPanelState` send the enum's canonical id while preserving the exact `showPanel` payload and tray-icon condition.

## 2. Enum-Keyed Granular State

- [x] 2.1 Replace the six private open notifiers and notifier-selection switches in `PanelController` with one map initialized from every `AlicePanel.values` member.
- [x] 2.2 Route `openListenable`, `_setOpen`, and `dispose` through the enum-keyed map while retaining all six named `ValueListenable<bool>` getters as source-compatible façades.
- [x] 2.3 Extend controller tests to verify every enum value has a stable initially-false listenable and that open, switch, close, no-op close, global notification, anchor, and disposal behavior remain unchanged.

## 3. Rebuild and Protocol Validation

- [x] 3.1 Run `flutter test test/panel_controller_test.dart test/rebuild_isolation_test.dart test/panel_command_view_map_test.dart test/alice_platform_channel_test.dart` and confirm exact granular notification/rebuild behavior and wire payloads.
- [x] 3.2 Verify `rg -n "_panelId|_mediaOpen|_clockOpen|_weatherOpen|_trayOverflowOpen|_notificationsOpen|_powerOpen" lib/app.dart lib/panel_controller.dart` returns no obsolete reverse mapping or per-panel storage fields while the public named getters remain.
- [x] 3.3 Run `dart format --output=none --set-exit-if-changed lib/panel_controller.dart lib/app.dart test/panel_controller_test.dart` followed by `flutter analyze` and the complete `flutter test` suite.
- [x] 3.4 Review the diff and confirm panel sizes remain owned by `lib/widgets/panels/panel_sizes.dart`; no panel ids, anchors, dimensions, public APIs, native/C++/generated files, manifests, lockfiles, dependencies, or persisted formats changed.
