## Why

Alice creates its only bar on the primary monitor and tries to infer a panel's output from a Flutter-local X coordinate. On multi-monitor Sway layouts, especially with differently sized outputs and non-zero output origins, that mismatch places panels at the wrong X coordinate. A bar on every active output should own panel placement for interactions originating from it.

## What Changes

- Create one top-layer bar surface for each monitor present when Alice starts.
- Route each Flutter bar view to its native monitor identity.
- Open the single global panel and its dismiss overlay on the monitor of the clicked bar, using an anchor local to that bar rather than virtual-desktop coordinates.
- Limit open-panel highlighting to the bar that invoked it.
- Preserve shared bar data and a single globally visible panel; defer monitor hot-plug, per-output workspace filtering, notification-placement changes, and non-layer-shell multi-monitor fallback behavior.

## Capabilities

### New Capabilities
- `multi-monitor-bars`: Render and route a bar surface for every monitor available at startup.

### Modified Capabilities
- `layer-shell-windowing`: Place bars and panels by their explicitly associated monitor rather than inferring a monitor from anchor coordinates.

## Impact

- C++ GTK runner: bar lifecycle, native surface/view registry, layer-shell monitor assignment, panel and dismiss-overlay geometry.
- Flutter: multi-view routing, bar source identity in panel anchors, and source-specific open-state presentation.
- Rust/FRB bridge: surface lifecycle metadata required to identify native bar views in Dart.
- Tests: native geometry and monitor/view routing tests plus Dart multi-view controller/routing coverage.
