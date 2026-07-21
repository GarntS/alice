## Why

Flutter state coordination currently repeats generated-model comparisons, popup synchronization, and configuration propagation across multiple owners. This creates schema-drift and missed-update risks—including weather offset changes being ignored—while making otherwise stateless widgets participate in application state mutation.

## What Changes

- Simplify snapshot comparators by using the generated structural equality already available for scalar-only models, while retaining explicit content comparison for nested lists and byte arrays.
- Make weather comparison include every render-observed field, including `WeatherSnapshot.offset`, without weakening content-based rebuild isolation.
- Make `NotificationPopupState` the single notification source for popup visibility mutations through Flutter's standard listenable mechanism, with one application listener coordinating popup projection and native window visibility.
- Make `AliceApp` the sole production owner of snapshot configuration updates; remove redundant `didUpdateWidget` propagation and convert `TopBar` and `AlicePanelCard` to stateless widgets.
- Preserve existing public constructors, state accessors, callback behavior, popup ordering/expiration semantics, and granular rebuild behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `snapshot-state`: Require complete content-aware comparison for render-observed snapshot fields and single-owner propagation of configuration-dependent derived state.
- `notification-popups`: Require one consistent visibility-change notification path for all popup mutation causes without duplicate notifications for no-ops.

## Impact

- Primary code: `lib/snapshot_state.dart`, `lib/notification_popup_state.dart`, `lib/app.dart`, `lib/widgets/top_bar.dart`, and `lib/widgets/panels/panel_host.dart`.
- Tests: `test/snapshot_state_test.dart`, `test/notification_popup_state_test.dart`, `test/notification_popups_test.dart`, `test/rebuild_isolation_test.dart`, `test/top_bar_snapshot_test.dart`, and panel rendering/command tests as needed.
- Generated bindings and native Rust code are not changed.
- No new dependency, persisted-data migration, protocol change, public API removal, or rollout step is expected.
