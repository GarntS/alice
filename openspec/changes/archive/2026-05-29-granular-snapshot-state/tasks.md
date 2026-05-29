## 1. Snapshot State Foundations

- [x] 1.1 Add test helpers for counting widget builds at named module boundaries.
- [x] 1.2 Add unit tests proving equivalent FRB-generated list contents do not notify when list instances differ.
- [x] 1.3 Add unit tests for CPU-only, memory-only, media-only, clock-only, network-only, workspace-only, tray-only, and notification-only slice notifications.
- [x] 1.4 Add unit tests for derived unread notification count, visible tray items, tray overflow count, and popup notification projections.
- [x] 1.5 Implement `AliceSnapshotState` with current snapshot-derived values, read-only slice listenables, ingestion, and disposal.
- [x] 1.6 Implement explicit comparators for workspaces, media, network, clock, tray items, notifications, and notification actions.
- [x] 1.7 Implement binary-data stabilization/comparison for tray icon bytes and notification image bytes to avoid false change notifications.
- [x] 1.8 Implement derived state recomputation for visible tray items, tray overflow count, unread notification count, and popup-visible notifications.
- [x] 1.9 Add config update handling for derived state affected by configuration, especially tray visible count and notification popup behavior.

## 2. Panel State Granularity

- [x] 2.1 Add tests for per-panel open-state notifications when opening, switching, and closing panels.
- [x] 2.2 Extend `PanelController` with granular read-only listenables for media, clock, tray overflow, notifications, and power open states.
- [x] 2.3 Ensure the existing single-open-panel semantics, anchor tracking, and native synchronization listener behavior remain intact.
- [x] 2.4 Add widget tests proving panel highlight changes rebuild only affected highlight consumers.

## 3. App Integration

- [x] 3.1 Instantiate and own `AliceSnapshotState` in `AliceApp` lifecycle, including disposal.
- [x] 3.2 Replace snapshot subscription root `setState` with `AliceSnapshotState.ingest(snapshot)`.
- [x] 3.3 Update notification popup window synchronization so root `setState` occurs only for platform view/window identity changes, not ordinary snapshot ingestion.
- [x] 3.4 Update config loading to refresh `AliceSnapshotState` derived configuration without forcing snapshot-driven widget rebuilds unrelated to config changes.
- [x] 3.5 Keep Rust `watchBarSnapshots` and the `BarSnapshot` transport unchanged.

## 4. Widget Refactor

- [x] 4.1 Refactor `TopBar` to receive `AliceSnapshotState` and granular panel listenables instead of a full `BarSnapshot`.
- [x] 4.2 Wrap each top-bar module in the narrowest `ValueListenableBuilder`/`ListenableBuilder` needed for its data and highlight state.
- [x] 4.3 Refactor media, clock, tray, and notification panels to subscribe only to the snapshot-state slices they consume.
- [x] 4.4 Refactor panel sizing and native `showPanel` synchronization to listen only to slices relevant to the currently open panel.
- [x] 4.5 Refactor notification popup rendering to subscribe to popup notification derived state instead of rebuilding from the full snapshot.
- [x] 4.6 Remove obsolete full-snapshot plumbing from widget constructors where no longer needed.

## 5. Rebuild Isolation Verification

- [x] 5.1 Add widget tests proving a CPU-only snapshot update rebuilds only CPU consumers and not unrelated bar modules, panels, or popups.
- [x] 5.2 Add widget tests proving media-only, clock-only, tray-only, and notification-only snapshot updates rebuild only their consumers.
- [x] 5.3 Add widget tests proving notification content changes that do not change unread count do not rebuild unread-count-only consumers.
- [x] 5.4 Add widget tests proving new but equivalent list instances from snapshots do not rebuild list consumers.
- [x] 5.5 Run `flutter test` and fix regressions.
- [x] 5.6 Run static analysis/formatting for changed Dart files and fix issues.
