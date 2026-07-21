## 1. Snapshot Comparison Workstream

- [x] 1.1 Extend `test/snapshot_state_test.dart` with a weather-offset-only regression and equivalent freshly allocated nested-weather coverage; assert weather notification counts and unchanged unrelated slices.
- [x] 1.2 In `lib/snapshot_state.dart`, delegate scalar-only public comparison helpers to verified generated `operator ==` implementations while preserving every helper signature.
- [x] 1.3 Keep explicit list and byte comparison for weather collections, tray icons, notification actions, and notification images; add `WeatherSnapshot.offset` to the weather comparison and verify all render-observed weather fields are covered.
- [x] 1.4 Run `flutter test test/snapshot_state_test.dart test/rebuild_isolation_test.dart` and confirm equivalent snapshots remain silent while changed fields notify only their consumers.

## 2. Popup Notification Workstream

- [x] 2.1 Extend `test/notification_popup_state_test.dart` to verify exact `Listenable` notification counts for batched snapshot changes, replacement, remove, hide-all, timer expiry, and no-op operations while retaining existing return values and timer semantics.
- [x] 2.2 Make `NotificationPopupState` in `lib/notification_popup_state.dart` a `ChangeNotifier`; batch `processSnapshot` emission, emit only for qualifying `remove`/`hideAll` operations, preserve the optional timer `onChanged` callback, and dispose timers/listeners safely.
- [x] 2.3 In `lib/app.dart`, register and remove one popup-state listener that updates `AliceSnapshotState.updatePopupVisibleIds` and invokes `_syncNotificationPopupWindow`; remove repeated synchronization from ingestion and popup action handlers without changing read/delete/action ordering.
- [x] 2.4 Add coverage in `test/snapshot_state_test.dart` or `test/notification_popups_test.dart` proving content-only changes to a visible notification refresh `popupNotifications` when the visible ID sequence is stable.
- [x] 2.5 Run `flutter test test/notification_popup_state_test.dart test/notification_popups_test.dart test/snapshot_state_test.dart` and verify FIFO-four, replacement timers, critical expiration, dismissal, action, and read-state behavior remain unchanged.

## 3. Configuration Ownership Workstream

- [x] 3.1 Add or adjust tests in `test/snapshot_state_test.dart` and `test/top_bar_snapshot_test.dart` to update reused snapshot state explicitly and verify config-dependent tray/popup projections recompute without consumer lifecycle side effects.
- [x] 3.2 Convert `TopBar` in `lib/widgets/top_bar.dart` to `StatelessWidget`, retain its public constructor/fields and nested granular builders, move `_probe` to the widget instance, and remove `didUpdateWidget` configuration mutation.
- [x] 3.3 Convert `AlicePanelCard` in `lib/widgets/panels/panel_host.dart` to `StatelessWidget`, retain its public constructor/fields and panel switch behavior, and remove `didUpdateWidget` configuration mutation.
- [x] 3.4 Confirm `lib/app.dart` initializes `AliceSnapshotState` with `_config` and remains the sole production caller that propagates a newly loaded config through `_snapshotState.updateConfig(config)`.
- [x] 3.5 Run `flutter test test/top_bar_snapshot_test.dart test/panels_rendering_test.dart test/panel_command_view_map_test.dart test/rebuild_isolation_test.dart` and confirm rendering and granular rebuild behavior remain unchanged.

## 4. Integrated Validation and Scope Guard

- [x] 4.1 Run `dart format --output=none --set-exit-if-changed` on the modified Dart source and test files, then run `flutter analyze`.
- [x] 4.2 Run the complete `flutter test` suite and confirm all tests pass with no Flutter rendering exceptions.
- [x] 4.3 Review the diff and confirm no changes were made to `lib/rust_gen/**`, `native/**`, manifests, lockfiles, persisted formats, platform protocols, dependencies, or unrelated UI behavior.
- [x] 4.4 Verify public constructors, comparator helper names/signatures, `NotificationPopupState` constructor/methods/returns, snapshot listenables, popup semantics, and rebuild-isolation expectations remain compatible.
