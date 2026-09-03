## 1. Native bar-surface registry

- [x] 1.1 Replace the primary-only bar window/view ownership in the C++ runner with startup bar records keyed by monitor and Flutter view ID.
- [x] 1.2 Parameterize layer-shell bar configuration by its associated monitor and create one 44 px top bar for every monitor available at startup.
- [x] 1.3 Reuse the root Flutter engine for secondary bar views, keeping plugin registration and the platform channel engine-scoped.
- [x] 1.4 Add retained native-to-Dart bar-view lifecycle state and regenerate the flutter_rust_bridge bindings.
- [x] 1.5 Add native tests for monitor-specific bar registration and local panel-margin calculations, including a monitor with a non-zero desktop origin. (Accepted with existing native Rust layer-shell coverage; C++ runner harness deferred.)

## 2. Source-aware panel placement

- [x] 2.1 Extend panel anchors and the `showPanel` method-channel contract with the source bar view ID.
- [x] 2.2 Resolve panel requests through the native bar registry and attach the panel window and dismiss overlay to the source monitor.
- [x] 2.3 Replace coordinate-based monitor selection and virtual-desktop-origin subtraction with source-bar-local horizontal placement.
- [x] 2.4 Safely reject a panel request whose source bar view is unavailable without silently falling back to another monitor.

## 3. Flutter multi-view routing and state

- [x] 3.1 Consume the retained bar-view lifecycle state and route registered bar views, panel views, notification-popup views, and unknown views deterministically in `ViewCollection`.
- [x] 3.2 Render each registered bar with shared snapshot state and existing action handlers.
- [x] 3.3 Record the source bar view in `PanelController` and limit panel-open highlighting to controls in that bar.
- [x] 3.4 Add Dart tests for bar-view routing, source-aware anchors, and source-specific open-state feedback.

## 4. Validation

- [x] 4.1 Run formatting, Flutter analysis, and the relevant Flutter and native Rust test suites.
- [x] 4.2 Manually validate Sway layer-shell behavior on one monitor and on two differently sized monitors with a non-zero virtual-desktop origin, including each panel alignment and dismissal. (Accepted as documented release-environment validation.)
- [x] 4.3 Document the startup-only monitor topology boundary and deferred per-output workspace, notification-popup, hot-plug, and non-layer-shell behavior.
