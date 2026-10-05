## Context

See proposal.md for motivation. Live Handy 0.9.1 exports org.kde.StatusNotifierItem at an Ayatana path, an absolute 64x64 PNG IconName, no Activate or ContextMenu method, and a com.canonical.dbusmenu Menu object. SecondaryActivate exists but its semantics belong to Handy. Current tray.rs chooses proxies without verifying interfaces, dispatches actions with call_noreply, and caches snapshots indefinitely. Flutter binds only onTap and catches action errors silently.

Alice uses separate GTK surfaces for bars and panels. ContextMenuController inserts an OverlayEntry into the current Flutter view; it cannot draw outside that view or create a native popup. Therefore a controller in the bar view alone cannot host the menu.

## Goals / Non-Goals

**Goals:** Generic protocol compatibility rather than Handy-specific logic; bounded asynchronous bus operations; unchanged-item caching; context-menu behavior on bar and overflow items across monitors.

**Non-Goals:** XEmbed support, arbitrary image-format/theme expansion, application-specific secondary-action labels, middle-click actions, failure notifications, and replacing existing watcher hosting.

## Decisions

### Verified item capabilities and reply-bearing actions

Discover each item's KDE/freedesktop interface and method set using introspection, confirming readable item properties rather than proxy construction. Cache verified metadata by canonical item identity and service owner; prefer KDE only when actually supported. If introspection is unavailable, successful property access can establish the interface and an explicit UnknownMethod/UnknownInterface reply can refine capabilities. Do not treat an unknown capability as definitely unsupported.

Expose typed activation outcomes (executed, unsupported/menu fallback, failed) to Flutter instead of inferring success from dispatch. Use asynchronous reply-bearing calls with a finite timeout (initially five seconds) off the UI thread. Fall back across interfaces only for explicit unsupported-interface/method responses, never for timeouts or arbitrary remote errors, avoiding duplicate application actions. Log destination, interface, method, and error without transcript/menu payload content. Avoid duplicate Rust/Flutter logs for the same failure.

Left-click honors ItemIsMenu, otherwise activates and falls back to the published menu only on confirmed unsupported activation. Right-click prefers a published menu and uses supported ContextMenu only if no usable menu can be loaded. No middle-click handler. Preserve direct action bridge compatibility with improved results.

Alternative rejected: always opening menus would change normal application activation; blindly trying methods with no replies masks failures.

### Exact paths and event-driven cached snapshots

Preserve valid pixmap priority. For an absolute IconName, load that exact filesystem path through the existing PNG scaler before theme-name lookup; never append an extension to a full path. Failed image reads retain fallback artwork, with bounded retries (initially every five seconds) rather than permanent negative caching. Keep current theme search and Ayatana fallback.

Maintain a runtime-owned asynchronous item registry with subscriptions for NewIcon, NewAttentionIcon, NewIconThemePath, NewTitle, NewStatus, and relevant PropertiesChanged, plus owner loss and registration changes. Mark affected cache entries dirty and trigger snapshot refresh; coalesce bursts and retain stable bytes for unchanged artwork. Subscribe before the initial read, using a generation check to avoid losing changes during reads. Refresh action/menu metadata when related properties change. Drop caches, capability metadata, subscriptions, and pending requests on disappearance. Prefer events over polling all properties every stats tick; only unresolved artwork gets periodic retry.

### D-Bus menu adapter and typed bridge

Keep protocol parsing, layout revisions, and event dispatch in Rust. Introduce bounded typed menu nodes carrying remote ids, labels, visibility/enabled states, separator type, toggle type/state, and children. Apply D-Bus menu defaults for omitted properties. Support AboutToShow where available before root/submenu refresh, GetLayout, LayoutUpdated, ItemsPropertiesUpdated, and clicked Event with protocol-compatible variant data and a timestamp. Validate remote trees with finite depth/node limits and reject malformed responses without crashing. Treat absent optional methods separately from service failures.

Expose load/refresh, scoped menu updates, selection, and cancellation through generated bindings. Identify requests by item identity, owner, and generation so late replies cannot reopen a dismissed or superseded menu. Synthetic actions are a separate typed action kind, never invented remote ids. Secondary action appears first only for supported SecondaryActivate and dispatches through the verified item interface. Subscribe for the active menu only and dispose subscriptions on closure. Menu updates must disable stale selections before rendering replacements.

Alternative rejected: passing raw D-Bus variants into Dart couples the UI to transport details and makes validation harder.

### Dedicated surface with Flutter context-menu overlay

Reuse native panel surface creation, anchoring, outside-click dismissal, and monitor selection for a dedicated tray-menu popup. Keep this transient popup under the existing single-open-popup coordinator rather than introducing an independent simultaneous popup lifecycle. Carry monotonically increasing request identities through native show/hide commands and Rust-to-Dart popup notifications; hide notifications name their originating request/view, and obsolete commands cannot clear or hide a newer popup. This shared bridge extension was approved during implementation after unscoped `None` hide notifications were found to permit stale dismissal. If current panel ids need extending, extend parsing, show/hide mapping, controller notifications, and tests atomically.

Render conventional vertical context-menu rows, not a dashboard card. Use ContextMenuController in the popup view to manage the root overlay; implement focus, arrows, Enter/Space, Escape, disabled states, toggle markers, and nested submenus in the menu widget. Allocate a surface region sufficient for submenus and clamp/flip placement at screen edges; scroll long menus within monitor bounds. Transparent unused surface areas must participate consistently in dismissal rather than accidentally blocking desktop interaction after closure.

Capture the source item's screen anchor and monitor before closing overflow. Carry logical Flutter anchors separately from SNI screen coordinates; convert using the existing native surface/scale information. A synthetic secondary-only published-menu absence does not manufacture an application menu: diagnose missing menu or use ContextMenu fallback as specified.

Alternative rejected: ContextMenuController directly in the bar is clipped to the bar surface; an independent native GTK menu would split Flutter styling and input ownership.

## Risks / Trade-offs

- [Popup geometry, focus, and monitor scaling] → Reuse native infrastructure; verify bar and overflow origins, edge placement, nested menus, keyboard focus, and mixed-scale monitors.
- [Untrusted or slow D-Bus publishers] → Timeouts, bounded trees, cancellation generations, and diagnostic-only failure paths.
- [Events arriving during reads or menu selection] → Subscribe before reads, coalesce dirty updates, and validate current generation/entry before dispatch.
- [SecondaryActivate semantics vary] → Generic Secondary action label; never infer Settings or another app-specific meaning.
- [Bridge and popup integration broaden the change] → Separate protocol/model tests from widget/surface tests; regenerate bindings in the same change.

## Migration Plan

No configuration or persisted-data migration is needed. Regenerate bindings with model/API changes and deploy Rust, Flutter, and runner changes together. Validate against fake session-bus publishers and live Handy plus conventional SNI applications. Roll back the change as a unit if popup behavior regresses; existing watcher registration must remain unchanged.
