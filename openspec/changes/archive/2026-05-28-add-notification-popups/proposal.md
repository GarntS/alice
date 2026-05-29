## Why

Alice already stores freedesktop notifications and renders them in the notification panel, but newly received notifications are only visible after the user notices the bar badge and opens the panel. Floating notification popups make incoming notifications immediately visible while preserving the existing notification list as the persistent history.

## What Changes

- Add floating notification popup cards that appear in a transparent top-right window below the bar plus `panel_top_gap_px`.
- Render popup cards with the same visual content and affordances as notification-list cards, including app/icon, timestamp, summary/body, action buttons, and the close button.
- Maintain at most 4 visible popups ordered oldest at top and newest at bottom; when a new popup arrives beyond the limit, bump the oldest visible popup while leaving it unread in the notification list.
- Auto-hide non-critical popups after `notifications.notification_display_time_ms`; timed auto-hide removes only the popup and leaves the notification unread.
- Support rightward drag dismissal that removes the popup, marks the notification read, and keeps it in the notification list.
- Keep critical notification popups visible by default; allow configured expiration with `notifications.expire_critical_notifications`.
- Hide visible popups when the notification panel opens.
- Add nested notification config keys: `show_notification_popup`, `notification_display_time_ms`, and `expire_critical_notifications`.
- Remove notification sound from scope.

## Capabilities

### New Capabilities
- `notification-popups`: Floating notification popup display, ordering, timeout, dismissal, and interaction behavior.

### Modified Capabilities
- `configuration`: Add typed nested notification popup configuration fields and defaults.
- `freedesktop-notifications`: Extend notification UI/user-action requirements to cover popup-specific interactions for stored freedesktop notifications.

## Impact

- Flutter UI: `AliceApp` snapshot handling, popup stack state, reusable notification card rendering, and popup interaction callbacks.
- Native windowing: Linux GTK/layer-shell runner likely needs a transparent popup window anchored top-right below the bar.
- Config: Rust config parsing/defaults, flutter_rust_bridge generated config types, Flutter config mapping, and shipped default config template.
- Tests/specs: configuration parsing/mapping tests and Flutter widget tests for popup ordering, timeout, dismissal, critical expiration, and panel-open hiding.
