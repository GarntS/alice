## Why

Rust snapshot updates currently enter Flutter through a root-level `setState`, so routine changes such as the 1 s CPU/memory tick can dirty and rebuild the active bar, panel, and popup subtrees. This rebuild churn is making Flutter builds/rebuilds extremely long and obscures which UI modules actually depend on changed data.

## What Changes

- Introduce a Flutter-side **snapshot state** object that ingests full `BarSnapshot` values, compares them against the current state, and publishes granular state slices only when those slices change.
- Refactor snapshot-driven widgets so they subscribe to the smallest state slice they consume instead of receiving the full `BarSnapshot` through `AliceApp`/`TopBar`.
- Replace root snapshot `setState` updates with snapshot-state ingestion; incoming snapshots must not dirty the application root solely because a new full snapshot arrived.
- Add derived state for UI-specific dependencies such as visible tray items, tray overflow count, unread notification count, and popup-visible notifications.
- Make panel highlight/open-state updates granular so toggling one panel only dirties widgets whose highlighted/open state changed.
- Add tests/instrumentation proving that single-slice snapshot changes mark only the affected widget builders dirty and leave unrelated widgets unrebuilt.

## Capabilities

### New Capabilities
- `snapshot-state`: Flutter-side granular snapshot state, diffing, derived state, and rebuild isolation for snapshot-driven UI.

### Modified Capabilities
- `panel-controller`: Add granular panel open/highlight state notifications so panel state changes do not rebuild unrelated bar modules.

## Impact

- Affected Flutter code: `lib/app.dart`, `lib/alice_platform.dart`, `lib/panel_controller.dart`, `lib/widgets/top_bar.dart`, bar module widgets, panel host/panel widgets, notification popup widgets, and Flutter tests.
- Affected generated/native APIs: none expected; Rust may continue emitting full `BarSnapshot` values over `watchBarSnapshots`.
- New internal APIs: snapshot-state object and slice listenables/selectors for raw and derived snapshot data.
- Testing impact: add rebuild-isolation tests and snapshot-state diff/derived-state unit tests.
