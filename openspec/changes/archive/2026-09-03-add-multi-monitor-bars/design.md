## Context

See proposal.md for motivation. The runner currently creates one bar window and Flutter treats view ID 0 as its sole bar. A panel anchor is calculated in the Flutter bar view, then the C++ runner compares that view-local coordinate against virtual-desktop monitor geometry. This crosses coordinate spaces and misplaces panels when the bar monitor has a non-zero desktop origin.

The existing runner already creates secondary `FlView`s for panels on the same Flutter engine, and Dart already renders a `ViewCollection`. The change can use those mechanisms for multiple bar views.

## Goals / Non-Goals

**Goals:**
- Represent every startup bar as a native surface associated with exactly one `GdkMonitor` and Flutter view ID.
- Make panel placement select that monitor explicitly and keep panel anchors local to its bar.
- Keep a single shared application state and a single globally visible panel.

**Non-Goals:**
- Dynamically add or remove bars after startup.
- Filter workspace chips by Sway output; existing snapshots do not preserve an output identity.
- Change notification-popup monitor policy.
- Guarantee multi-monitor behavior in the non-layer-shell GTK fallback.

## Decisions

### Maintain a native bar-surface registry

The C++ runner will replace its singular bar-window/view fields with bar records keyed by monitor and by Flutter view ID. A record owns the bar GTK window, its `FlView`, and the associated `GdkMonitor`.

At startup, the runner enumerates display monitors and creates one bar record per monitor. One view creates the Flutter engine; all remaining bar and panel views use that engine. Plugins and the platform channel remain engine-scoped and are registered once.

This is chosen over inferring the monitor from coordinates because native view IDs have an unambiguous owning monitor. It is also chosen over separate application processes/engines because the current shared-engine multi-view model already supports panels and shares application state efficiently.

### Synchronize bar view identities to Dart as a lifecycle snapshot

The Rust/FRB bridge will expose bar-view lifecycle state, backed by a retained registry that C++ updates through its existing C ABI bridge pattern. A subscriber receives the complete current bar-view set immediately, then later updates if supported by the implementation.

A retained snapshot avoids a startup race in which secondary bar views are created before Dart subscribes. Dart will render a bar only for registered bar IDs; it will continue to route notification and panel views explicitly, with unknown views rendering empty.

### Carry source bar identity with a panel anchor

`PanelAnchor` and the `showPanel` method-channel payload will include the Flutter view ID of the bar that produced the click. The anchor X coordinate remains local to that bar.

The panel controller records the source view ID with the open panel. `TopBar` receives its bar view ID and treats an open state as highlighted only if that ID matches the controller's source.

This is chosen over passing monitor geometry to Dart or converting anchors to virtual-desktop coordinates: Dart does not own native monitor identity, and native placement must not depend on virtual-desktop origin.

### Resolve panel and dismiss-overlay monitor through the source view

When C++ receives `showPanel`, it resolves the supplied source view ID in the native bar registry. It attaches both the reusable panel window and the single dismiss overlay to that exact monitor. Horizontal margins use the source bar's local width and local anchor; they do not read `geometry.x` or `geometry.y`.

The application retains one global visible panel. Opening a panel from a different bar hides or reuses the current panel and moves it, together with its overlay, to the new source monitor.

### Preserve current shared content and startup-only topology

All bars consume the same existing snapshot state. In particular, workspace chips continue to use the unfiltered shared workspace list, notification popups retain their current monitor behavior, and monitor hot-plug is deferred. This avoids requiring an unreliable GTK-monitor to Sway-output identity mapping in this change.

## Risks / Trade-offs

- [Mixed-DPI outputs can expose a Flutter-logical versus GTK allocation-unit mismatch] → Validate local-anchor and panel-width units on mixed-scale Sway outputs before declaring support; retain explicit source-monitor routing regardless.
- [A missing or stale source view ID could make a panel unplaceable] → Reject the panel show request safely and keep native/Dart panel state synchronized rather than falling back to the primary monitor.
- [Multiple Flutter bar trees increase rebuild work] → Share the existing snapshot state and retain granular listenables; validate that each bar only rebuilds the consumers affected by a snapshot change.
- [Startup-only monitor enumeration leaves hot-plug topology stale] → Document restart as the boundary and add monitor lifecycle handling in a later change.

## Migration Plan

1. Replace the primary-only bar initialization with startup monitor enumeration while preserving the existing primary monitor as the initial/root Flutter view.
2. Add bar lifecycle routing in Dart before exposing multiple bar windows, so every native view has a deterministic widget role.
3. Add source-view panel payloads and native registry lookup, then remove monitor selection by anchor containment and origin subtraction.
4. Validate single-monitor behavior, then validate a two-monitor Sway layout with differing resolutions and non-zero monitor origins.

Rollback is a package downgrade to the primary-only runner; this change introduces no persisted user configuration or data migration.
