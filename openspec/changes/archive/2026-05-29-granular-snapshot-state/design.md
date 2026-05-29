## Context

Alice currently receives full `BarSnapshot` objects from Rust over `watchBarSnapshots`. `_AliceAppState` stores the latest snapshot and calls root-level `setState` for every snapshot, then passes the full snapshot through `TopBar`, `AlicePanelCard`, and notification popup builders. This means a single CPU/memory tick can dirty and rebuild unrelated media, workspace, tray, clock, panel, and popup widgets.

The Rust runtime already debounces event bursts and emits a complete snapshot. This change does not need to alter that transport. The performance issue is Flutter-side invalidation granularity: Dart treats each full snapshot as an app-level state change instead of splitting it into UI-consumable slices.

## Goals / Non-Goals

**Goals:**
- Introduce a Dart-side `AliceSnapshotState` that owns the current snapshot-derived state and exposes granular listenables.
- Ensure snapshot ingestion does not call root `setState` and does not mark unrelated widgets dirty.
- Refactor bar, panel, and popup rendering so widgets subscribe only to the state slices they consume.
- Diff incoming snapshots with explicit comparators, including deep list comparison for generated FRB list fields.
- Publish derived state needed by UI modules, such as visible tray items, tray overflow count, unread notification count, and visible popup notifications.
- Make panel open/highlight state granular so panel toggles dirty only affected highlighted modules and panel surfaces.
- Add tests that prove rebuild isolation for representative single-slice changes.

**Non-Goals:**
- Changing the Rust `BarSnapshot` schema or `watchBarSnapshots` stream shape.
- Reducing Rust snapshot construction cost or FRB serialization/deserialization cost.
- Introducing a third-party state-management dependency unless implementation discovers a strong need.
- Optimizing non-snapshot changes such as initial config load, theme changes, or platform view collection changes beyond preserving existing behavior.

## Decisions

### Use `AliceSnapshotState`, not a snapshot store

The new object SHALL be named `AliceSnapshotState` because it represents the current UI state derived from the latest snapshot, not a collection/history of snapshots. It may retain the previous/current values needed for diffing, but it is conceptually the live snapshot state.

Alternative considered: `SnapshotStore`. Rejected because "store" implies multiple stored snapshots or persistence, which is not the intent.

### Keep Rust transport full-snapshot; split in Dart

Rust will continue emitting full `BarSnapshot` values. Dart will split each received snapshot into independently notified slices.

```
Rust BarSnapshot
      │
      ▼
AliceSnapshotState.ingest(next)
      │
      ├─ cpuUsageCores notifier
      ├─ memoryUsagePercent notifier
      ├─ media notifier
      ├─ workspaces notifier
      ├─ network notifier
      ├─ clock notifier
      ├─ trayItems / visibleTrayItems / overflowCount notifiers
      └─ notifications / unreadCount / popupNotifications notifiers
```

Alternative considered: change Rust to emit field-level events. Rejected for this change because the existing full snapshot is a useful consistency boundary, Rust already debounces it, and the observed churn is caused by root Flutter invalidation.

### Publish small `ValueListenable` slices

`AliceSnapshotState` should expose stable `ValueListenable<T>` interfaces for each raw and derived slice. Internally, each slice can be a `ValueNotifier<T>` or another small `ChangeNotifier`-backed primitive. The public surface should encourage widgets to subscribe to the narrowest useful type.

Representative slices:
- `ValueListenable<double> cpuUsageCores`
- `ValueListenable<double> memoryUsagePercent`
- `ValueListenable<MediaSnapshot?> media`
- `ValueListenable<List<WorkspaceSnapshot>> workspaces`
- `ValueListenable<NetworkSnapshot> network`
- `ValueListenable<ClockSnapshot> clock`
- `ValueListenable<List<TrayItemSnapshot>> visibleTrayItems`
- `ValueListenable<int> trayOverflowCount`
- `ValueListenable<List<NotificationSnapshot>> notifications`
- `ValueListenable<int> unreadNotificationCount`
- `ValueListenable<List<NotificationSnapshot>> popupNotifications`

Widgets should use `ValueListenableBuilder`/`ListenableBuilder` at the module boundary. A changed notifier marks only that builder subtree dirty.

### Avoid full-snapshot props in snapshot-driven widgets

`TopBar` should receive configuration, actions, panel state, and `AliceSnapshotState`, but it should not receive a full `BarSnapshot`. It should lay out module boundaries and place builders around individual modules.

Panels should follow the same pattern:
- Media panel listens to `media`.
- Clock panel listens to `clock` plus config/calendar-local state.
- Tray panel listens to tray items/overflow data.
- Notification panel listens to notifications.
- Power panel does not listen to snapshot data.

Panel sizing that depends on snapshot slices should subscribe only to those slices. For example media panel height depends on `media`; tray overflow height depends on tray overflow count; notification panel sizing depends on notification count if dynamic sizing is kept.

### Make derived state explicit

Some UI modules consume a projection rather than raw snapshot data. `AliceSnapshotState` should compute and publish those projections so parent widgets do not recompute them during broad builds.

Examples:
- `visibleTrayItems` and `trayOverflowCount` depend on `trayItems` and `config.maxVisibleTrayItems`.
- `unreadNotificationCount` depends on `notifications`.
- `popupNotifications` depends on `notifications` and popup-visible ids.

When config affects derived state, `AliceSnapshotState` should provide an `updateConfig(AliceConfig config)` or narrower config update method. Updating config may notify affected derived slices, but incoming snapshot updates must not trigger unrelated config/theme rebuilds.

### Use explicit comparators for FRB-generated objects and lists

FRB-generated model classes compare scalar/object fields, but Dart `List ==` is identity equality. Since each snapshot can contain fresh list instances, `AliceSnapshotState` must use explicit comparators for list fields.

Comparator rules:
- Compare primitive/scalar fields directly.
- Compare object fields using their generated equality when safe.
- Compare lists by length and element contents.
- Treat tray icon bytes and notification image bytes carefully: use stable references/caches where possible; avoid repeated full byte scans on every snapshot.
- Preserve or move existing tray icon stabilization from `AlicePlatform._stabiliseIcons` so unchanged icon bytes do not cascade into false tray changes.

### Granular panel open state

`PanelController` currently exposes one broad `ChangeNotifier`. This is useful for native show/hide synchronization, but it is too coarse for highlight rendering. The controller should additionally expose per-panel listenables or equivalent selectors:

```
mediaOpen
clockOpen
trayOverflowOpen
notificationsOpen
powerOpen
```

When the open panel changes, only the previously open panel and newly open panel notifiers should fire. The native synchronization listener may still listen to the broad controller/open-panel state, but bar module highlight widgets should listen to per-panel open state.

### Keep application root stable during snapshot ingestion

`_AliceAppState` may still call `setState` for lifecycle changes that affect the view collection, config/theme load, panel view id mapping, or notification popup window id. It must not call `setState` solely because a snapshot arrived. Snapshot subscription should become:

```
_snapshotSubscription = platform.watchBarSnapshots().listen((snapshot) {
  snapshotState.ingest(snapshot);
  syncNotificationPopupWindowIfVisibilityChanged();
});
```

The exact popup sync mechanism can be callback/listener based, but it should not dirty the root unless the set of platform views or popup view id actually changes.

## Risks / Trade-offs

- Broader state API surface → Keep `AliceSnapshotState` focused on snapshot-derived state and expose read-only `ValueListenable`s to widgets.
- False positives in diffing due to list identity or byte identity → Use explicit list comparators and byte stabilization/caching for icon/image fields.
- False negatives from overly coarse derived comparisons → Add unit tests for each comparator and derived notifier.
- More builders in the widget tree → Accept small builder overhead to gain much smaller dirty/rebuild scopes; keep builders at module boundaries rather than around every leaf.
- Panel sizing and native showPanel synchronization may need snapshot-dependent updates → Subscribe synchronization code to only the slices needed for the open panel and recompute native geometry when those slices change.
- Notification popup state currently calls root callbacks → Convert popup-visible ids/notifications to granular listenables and restrict root updates to native window visibility/view-id changes.
