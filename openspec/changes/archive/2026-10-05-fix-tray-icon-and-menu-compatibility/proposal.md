## Why

Live Handy 0.9.1 debugging shows that its tray item registers correctly, but Alice cannot load its absolute-path icon and invokes an unsupported Activate method instead of consuming its published menu. Hidden action errors and indefinitely cached snapshots make these compatibility failures harder to diagnose and can leave artwork stale.

## What Changes

- Load absolute PNG IconName paths directly while preserving pixmap priority and existing theme-name resolution.
- Verify KDE/freedesktop item interfaces and supported methods rather than treating proxy construction as capability discovery.
- Use reply-bearing, bounded action calls with structured diagnostics and safe unsupported-method fallback.
- Left-click activates, falling back to the published menu; menu-only items open the menu directly. Right-click opens the menu. Do not bind middle-click.
- Render published com.canonical.dbusmenu menus in a normal-looking Flutter context menu hosted on a dedicated popup surface, reusing Alice's native surface infrastructure.
- Add a synthetic Secondary action entry at the top only when SecondaryActivate is supported.
- Refresh cached item data on SNI changes, retry missing artwork, and clean up subscriptions on item disappearance.

## Capabilities

### New Capabilities
- `tray-context-menus`: Published D-Bus menu loading, rendering, events, updates, and dedicated popup lifecycle.

### Modified Capabilities
- `status-notifier-tray`: Absolute-path icon resolution, verified interfaces, cache invalidation, click routing, and observable action outcomes.

## Impact

Rust tray/runtime and bridge APIs, generated Flutter bindings, tray snapshots, Flutter bar/overflow interactions, and GTK popup surface integration are affected. Existing watcher hosting and normal application activation remain supported. No new user configuration or notifications are introduced; failures are diagnostic-only. No application implementation is included in this planning change.
