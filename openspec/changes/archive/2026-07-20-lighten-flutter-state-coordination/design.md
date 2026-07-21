## Context

Three independent sources of coordination weight are being changed together by explicit packaging choice:

1. `AliceSnapshotState.ingest` uses public helper functions in `lib/snapshot_state.dart` to compare generated FRB models. Scalar-only generated models already implement field-wise `operator ==`, but the Flutter state repeats those fields manually. Collection-owning generated models still require explicit content comparison because generated list and `Uint8List` equality is identity-based. The current weather comparator omits `WeatherSnapshot.offset`, although `WeatherPanel` uses that value when formatting and selecting forecast entries.
2. `NotificationPopupState` reports timer changes through `onChanged`, while callers use boolean returns and manually repeat projection/window synchronization. `AliceApp` currently has six popup-ID projection calls and six popup-window synchronization calls.
3. `AliceApp`, `TopBar.didUpdateWidget`, and `AlicePanelCard.didUpdateWidget` all call `AliceSnapshotState.updateConfig`. The application already supplies the initial config and explicitly updates the state after async config loading; the child widgets otherwise need no mutable state.

The repository is `publish_to: none`, but existing public Dart constructors, methods, getters, callbacks, and comparison helpers are treated as compatibility constraints. Existing snapshot and panel tests demonstrate that granular notifications and rebuild isolation are required behavior.

## Goals / Non-Goals

**Goals:**

- Reduce duplicated schema knowledge while preserving content-based equality for generated collections and bytes.
- Ensure every render-observed weather field, including `offset`, participates in weather change detection.
- Route all popup visibility mutations through one standard Flutter listenable path and one application listener.
- Establish `AliceApp` as the sole production owner of snapshot configuration propagation.
- Preserve popup semantics, public API shapes, and narrow rebuild behavior.
- Keep all three workstreams independently reviewable within this combined change and validate their interaction.

**Non-Goals:**

- Do not edit `lib/rust_gen/**`, `native/**`, FRB generation settings, manifests, or dependencies.
- Do not replace collection-aware equality with generated top-level equality; generated list/byte fields remain identity-based.
- Do not change snapshot data formats, native panel/window protocols, notification storage/read semantics, popup limits/order/timers, or panel rendering.
- Do not remove or rename public comparator helpers, `NotificationPopupState` methods/constructor parameters, snapshot listenables, or widget constructor parameters.
- Do not redesign `AliceSnapshotState`, merge its granular notifiers, or broaden widget rebuilds.

## Decisions

### 1. Delegate only scalar-safe comparisons to generated equality

Keep `listEqualsBy`, `bytesEqual`, and all existing public type-specific helper names. Implement scalar-only helper bodies by delegating to the generated model's `operator ==` (including nullable values where Dart equality already handles null). This applies to `WorkspaceSnapshot`, `MediaSnapshot`, `NetworkSnapshot`, `ClockSnapshot`, `WeatherPoint`, `WeatherDay`, `WeatherAlert`, and `NotificationActionSnapshot` after verifying each generated equality covers only scalar/enum/string/nullable-scalar fields.

Keep explicit structural comparison for:

- lists of generated objects;
- `TrayItemSnapshot.iconPngBytes`;
- `NotificationSnapshot.actions` and `imageData`;
- `WeatherSnapshot.hourly`, `daily`, and `alerts`.

`weatherSnapshotsEqual` must compare `latitude`, `longitude`, `timezone`, `offset`, `units`, `lastUpdatedUnixSecs`, `currently`, and all three collection fields. Public helper signatures stay unchanged, so internal and external callers remain source-compatible.

Alternative considered: use generated `WeatherSnapshot.operator ==` directly. Rejected because generated `List` equality is identity-based and would violate the existing equivalent-list requirement.

Alternative considered: add a deep-equality dependency. Rejected because the present generated leaf equality plus small collection-aware glue is clearer and adds no dependency or dynamic comparison behavior.

### 2. Make `NotificationPopupState` a `ChangeNotifier` without changing its public mutation API

Have `NotificationPopupState` extend `ChangeNotifier`. Preserve the constructor, mutable `config`, `visibleIds`, `processSnapshot`, `remove`, `hideAll`, `dispose`, and the optional `onChanged` callback.

Notification rules:

- A public operation emits `notifyListeners()` exactly once when it reports a popup visibility event/change.
- `processSnapshot` batches stale removals and enqueues/replacements into one notification, matching its existing aggregate boolean result. A replacement may notify even when the final ID sequence is unchanged because its timer/window event is renewed.
- `remove` notifies only when an ID was visible; timer cancellation alone is not a visible change.
- `hideAll` notifies only when at least one popup was visible.
- Timer expiry uses the same `remove` path. Preserve the legacy `onChanged` timer callback behavior for compatibility, but `AliceApp` will no longer supply that callback, preventing duplicate application synchronization.
- `dispose` cancels timers and clears state without notifying disposed listeners, then calls `super.dispose()`.

In `AliceApp`, register one popup-state listener during initialization and remove it before popup-state disposal. That listener calls `AliceSnapshotState.updatePopupVisibleIds` and starts `_syncNotificationPopupWindow`. Remove the repeated projection/window calls from snapshot ingestion, hide-all, popup dismiss, notification dismiss, and popup action handlers.

This remains correct for content-only notification updates: `AliceSnapshotState.ingest` updates `_notifications` and invokes `_recomputeNotificationDerived`, which already recomputes `_popupNotifications` from the existing visible IDs before `processSnapshot` runs. A subsequent visibility event updates IDs through the centralized listener.

Keep asynchronous window synchronization fire-and-forget as today; do not serialize or reorder native calls in this change.

Alternative considered: move popup projections out of `AliceSnapshotState`. Rejected because that would remove or reshape public snapshot APIs and couple this refactor to a broader state redesign.

### 3. Make application configuration propagation explicit and single-owner

Keep initial configuration injection through `AliceSnapshotState(config: _config)`. Keep the explicit `_snapshotState.updateConfig(config)` in `AliceApp._loadConfig` after a successfully loaded config becomes current.

Remove `didUpdateWidget` configuration mutation from `TopBar` and `AlicePanelCard`. Convert both to `StatelessWidget` while retaining their class names, constructors, fields, and rendered child trees. Move `_probe` to a private instance method on `TopBar`; replace `widget.<field>` references with direct fields. `AlicePanelCard` builds directly from its fields.

Callers outside `AliceApp` remain responsible for calling `updateConfig` when reusing an `AliceSnapshotState` with a changed config. Tests that intentionally exercise config-dependent state must update the state explicitly rather than relying on a consumer widget lifecycle side effect.

Alternative considered: keep one child widget as fallback owner. Rejected because ownership would remain implicit and behavior would depend on which consumer happened to rebuild first.

### 4. Preserve interaction boundaries across the combined change

The popup listener may call `updatePopupVisibleIds`, while config updates can trigger notification/tray derived recomputation. Both paths must retain equality guards so a no-op projection/config update emits no derived notifier event. Equality simplification must be completed without broadening raw or derived notifications, because popup and stateless-widget tests rely on those boundaries.

## Risks / Trade-offs

- [Generated equality changes in a future FRB release] → Keep focused comparator tests for equivalent fresh instances and field changes; never delegate collection-owning model equality wholesale.
- [Popup operations notify twice through `ChangeNotifier` and legacy `onChanged`] → Do not pass `onChanged` from `AliceApp`; test exact listener counts for every mutation cause and preserve the legacy callback only for external compatibility.
- [Content-only popup changes could be missed after removing manual ID refresh] → Retain and test `AliceSnapshotState.ingest` recomputation of popup projections whenever notification content changes with stable visible IDs.
- [A caller relied on widget rebuilds to propagate config] → Preserve public `updateConfig`, document the owner invariant in tests/specs, and add a direct config-update regression test before converting widgets.
- [Stateless conversion accidentally broadens rebuilds] → Keep the existing nested `ValueListenableBuilder` tree intact and run rebuild-isolation tests.
- [Combined change obscures failures between workstreams] → Structure tasks and tests by workstream, then run integrated analysis and the complete Flutter test suite.

## Migration Plan

No data, protocol, dependency, or deployment migration is required. Implement comparator changes, popup notification centralization, and widget ownership cleanup as separate commits or review units inside the one OpenSpec change. Rollback is source-level: each workstream can be reverted independently if its focused tests fail.

## Open Questions

None. If implementation inspection shows generated equality for any proposed scalar leaf contains a collection or identity-sensitive field, retain that helper's explicit field comparison and add a test rather than changing generated code.
