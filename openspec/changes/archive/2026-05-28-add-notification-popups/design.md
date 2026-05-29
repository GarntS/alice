## Context

Alice currently receives freedesktop notifications in Rust, stores them in memory, exposes them through `BarSnapshot.notifications`, and renders them in the Flutter notification panel. The panel card already contains most of the desired visual elements: app name, icon/image, received time, summary/body, actions, and a hover close affordance. The main bar window is a 44 px layer-shell surface and panel windows are separate transparent layer-shell windows created by the Linux runner.

Popup notifications need to float below the bar and can be taller than the bar surface, so rendering them only inside the bar view risks clipping. The popup UI also needs local state that differs from the persistent notification store: a popup can disappear because of timeout or FIFO overflow while the stored notification remains unread and visible in the panel.

## Goals / Non-Goals

**Goals:**
- Display newly received or replaced notifications as floating cards in a transparent top-right window below the bar plus `panel_top_gap_px`.
- Reuse the visual language and content of existing notification panel cards, including action buttons and close affordance.
- Keep popup visibility state separate from notification storage/read state.
- Enforce a 4-popup FIFO visible stack ordered oldest at top and newest at bottom.
- Support timeout behavior, critical notification persistence, drag-to-read dismissal, action-click mark-read behavior, and panel-open popup hiding.
- Add typed nested `notifications` config fields and defaults in Rust and Flutter.

**Non-Goals:**
- Notification sounds or audio assets.
- Persisting notifications or popup state across application restarts.
- Implementing a full notification center beyond the existing panel.
- Changing freedesktop notification server registration or D-Bus action/closed signal semantics beyond existing user actions.

## Decisions

### Use a dedicated transparent popup layer-shell window

Create or extend native window management with a transparent, non-focusable popup window anchored top-right. Its top margin is the bar height plus `panel_top_gap_px`, its width matches the notification panel width (`380`), and its height stretches to the bottom of the display to avoid clipping a four-popup stack.

Alternative considered: render popups in the existing bar Flutter view. This is simpler in Dart, but the 44 px bar surface can clip cards and does not model desktop notification geometry well. A dedicated window matches the existing panel architecture and keeps the bar surface size stable.

### Keep popup stack state in Flutter

Flutter receives every `BarSnapshot`, compares the current notification list against previously seen notification ids/content, and maintains a popup-visible list of notification ids. New notifications and replacement notifications enqueue a popup. If the visible list exceeds four items, Flutter removes the oldest visible popup while leaving the underlying notification untouched.

Alternative considered: track popup state in Rust. Rust owns notification storage, but popup behavior is view state tied to rendering, timers, gestures, and panel visibility. Keeping it in Flutter avoids mixing UI lifecycle with the D-Bus server store.

### Detect replacements as popup events and reset timers

When a notification id remains present but its received timestamp/content changes because `replaces_id` updated the stored notification, Flutter treats it as a popup event. If already visible, the popup remains in the stack but its display timer resets. If not visible, it is enqueued as a new visible popup subject to FIFO overflow.

This favors making updated notifications noticeable over suppressing progress updates. The trade-off is that rapidly replacing notifications can remain visible for longer; the timer reset behavior is explicit and testable.

### Factor notification card rendering for panel and popups

Extract the reusable card body from the current private panel card into a shared widget that accepts behavior callbacks for close, body tap, action tap, and optional dismissible wrapping. The panel and popup can then share visual rendering while keeping semantics distinct.

Panel close continues to delete/dismiss the notification. Popup close also deletes/dismisses. Popup body click marks the notification read. Popup action click invokes the action and marks the notification read. Rightward drag marks read and removes only the popup.

### Use Flutter `Dismissible` for rightward drag

Wrap popup cards in `Dismissible` with `DismissDirection.startToEnd` and an explicit threshold. On dismiss, remove the popup and call the existing mark-read API. Timed expiration and FIFO overflow remove only the popup without marking read.

### Add popup config under `notifications`

Extend `NotificationConfig` with:
- `show_notification_popup: bool` default `true`
- `notification_display_time_ms: u32` default `5000`; `0` means never auto-expire
- `expire_critical_notifications: bool` default `false`

`default_timeout_ms` remains the server-side freedesktop expiration setting and does not control popup display duration.

## Risks / Trade-offs

- **Native window complexity** → Model the popup window after existing panel layer-shell window setup, but keep it independent from panel open/close state and non-focusable.
- **Flutter multi-view lifecycle edge cases** → Reuse the existing `ViewCollection` pattern and map the popup window view id to a dedicated popup view, similar to panel view mapping.
- **Timer leaks or stale callbacks** → Store timers by notification id, cancel on popup removal, replacement, panel open, and widget disposal, and verify `mounted` before mutating state.
- **Gesture/button conflicts inside dismissible cards** → Limit `Dismissible` to horizontal rightward drag, keep action buttons tappable, and test action taps separately from drag dismissal.
- **Rapid replacement notifications keep resetting timers** → This is intentional per requirements; critical/non-critical expiration rules still apply.
- **Popup state diverges from store after deletion** → On every snapshot update, prune popup ids that no longer exist in `BarSnapshot.notifications`.
