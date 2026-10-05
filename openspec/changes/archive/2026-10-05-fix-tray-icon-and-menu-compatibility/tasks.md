## 1. Item discovery and action outcomes

- [x] 1.1 Add verified KDE/freedesktop interface and method discovery, including unavailable-introspection fallback and owner-scoped metadata.
- [x] 1.2 Replace no-reply action dispatch with asynchronous bounded reply-bearing calls and typed execution/unsupported/failure outcomes; prevent duplicate retries after ambiguous failures.
- [x] 1.3 Add diagnostic context for actions and remove silent Flutter error swallowing without adding user notifications.
- [x] 1.4 Test KDE-only, freedesktop-only, unsupported methods, unavailable introspection, remote errors, and timeout behavior using fake D-Bus publishers.

## 2. Artwork and item lifecycle

- [x] 2.1 Load absolute PNG IconName paths exactly, preserving pixmap priority, scaling, theme names, and Ayatana fallback; test missing and corrupt files.
- [x] 2.2 Introduce runtime-owned item subscriptions and dirty-cache refresh for icon/title/status/property changes with burst coalescing and read-generation protection.
- [x] 2.3 Add bounded retry for missing artwork and owner-loss/registration-removal cleanup for caches, capabilities, subscriptions, and pending requests.
- [x] 2.4 Test initially missing artwork recovery, changing icons/titles/status, stable unchanged bytes, and item disappearance.

## 3. D-Bus menu protocol

- [x] 3.1 Add typed bounded menu-tree parsing with property defaults, visibility/enabled states, separators, nested children, and check/radio states.
- [x] 3.2 Implement root/submenu AboutToShow preparation, GetLayout loading, layout/property updates, and active-menu scoped subscriptions.
- [x] 3.3 Implement validated clicked Event dispatch and a distinct synthetic Secondary action invoking supported SecondaryActivate.
- [x] 3.4 Add owner/request-generation cancellation and malformed/slow publisher handling; test updates, stale ids, payloads, unsupported optional methods, and teardown.

## 4. Bridge and input routing

- [x] 4.1 Expose menu load/update/select/cancel APIs and item capability/activation outcomes; regenerate bindings and update snapshot comparisons where metadata changes.
- [x] 4.2 Add consistent left/right-click handling on bar and overflow: activate with menu fallback, ItemIsMenu direct menu, right-click menu then supported ContextMenu fallback, and no middle-click dispatch.
- [x] 4.3 Capture source anchors/monitor before overflow closure and preserve screen-coordinate conversion for direct and synthetic SNI actions.
- [x] 4.4 Test input routing, menu-only items, absent menus, supported/unsupported secondary actions, and bridge error propagation.

## 5. Context-menu popup

- [x] 5.1 Extend existing popup coordination/native surface plumbing for a dedicated tray-menu surface, preserving single-open-popup semantics and monitor placement.
- [x] 5.2 Render a conventional context menu using ContextMenuController inside the popup view, including separators, disabled entries, toggles, and the conditional top Secondary action entry.
- [x] 5.3 Implement nested submenu placement, edge flipping/clamping, long-menu scrolling, keyboard focus/navigation/activation, Escape, and outside-click dismissal.
- [x] 5.4 Handle live updates, superseded loads, service disappearance, and cleanup without stale actions or empty input-blocking surfaces.
- [x] 5.5 Add widget/controller/native-channel tests for bar and overflow origins, popup replacement, submenu bounds, keyboard behavior, and complete dismissal.

## 6. Integration verification

- [x] 6.1 Run targeted tray/menu Rust tests, the alice_platform suite, Flutter analyzer/tests, binding generation checks, and Linux build checks; use nix develop when required.
- [x] 6.2 Verify live Handy artwork, left-click menu fallback, right-click menus, nested model choices, Secondary action dispatch, and diagnostic-only failures without destructive menu selections.
- [x] 6.3 Verify conventional Activate-capable SNI apps retain behavior and exercise multi-monitor/mixed-scale placement, icon updates, owner loss, and popup focus/dismissal.
- [x] 6.4 Record verification results and run strict OpenSpec validation before declaring implementation complete.
