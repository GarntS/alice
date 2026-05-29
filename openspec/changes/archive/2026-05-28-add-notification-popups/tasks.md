## 1. Configuration

- [x] 1.1 Extend Rust `NotificationConfig` and raw YAML parsing with `show_notification_popup`, `notification_display_time_ms`, and `expire_critical_notifications` defaults.
- [x] 1.2 Update `assets/config/default_config.yaml` with documented nested notification popup keys.
- [x] 1.3 Regenerate/update flutter_rust_bridge config bindings and map the new notification fields into Flutter `AliceConfig`.
- [x] 1.4 Add or update Rust and Flutter config tests for omitted and explicit notification popup settings.

## 2. Native Popup Window

- [x] 2.1 Add Linux runner support for a transparent non-focusable notification popup window using the existing engine and a separate Flutter view.
- [x] 2.2 Anchor the popup window top-right with top margin equal to bar height plus `panel_top_gap_px`, width equal to the notification panel width, and enough height for four popup cards.
- [x] 2.3 Add platform channel methods and/or panel command plumbing for showing, hiding, and mapping the popup window view id to Dart.
- [x] 2.4 Ensure popup window visibility is independent from panel windows and does not take focus or reserve exclusive screen space.

## 3. Shared Notification Card UI

- [x] 3.1 Refactor notification panel card rendering into reusable card/body widgets without changing existing panel appearance or behavior.
- [x] 3.2 Add popup-specific card behavior: body click marks read, action click invokes action and marks read, close click dismisses/deletes notification.
- [x] 3.3 Wrap popup cards with rightward Flutter `Dismissible` behavior that removes only the popup and marks the notification read.

## 4. Popup Stack State

- [x] 4.1 Track previously seen notification snapshots in `AliceApp` and detect new notifications and replacements as popup events.
- [x] 4.2 Maintain visible popup ids ordered oldest-to-newest, enforce a maximum of four, and bump the oldest visible popup on overflow.
- [x] 4.3 Prune visible popups when their notifications no longer exist in `BarSnapshot.notifications`.
- [x] 4.4 Respect `notifications.show_notification_popup` by suppressing popup creation while still leaving notifications in the list.

## 5. Timers and Lifecycle

- [x] 5.1 Add per-popup display timers using `notifications.notification_display_time_ms`, treating `0` as never auto-expire.
- [x] 5.2 Reset popup timers when replacement notifications are received.
- [x] 5.3 Keep critical popups from auto-expiring unless `notifications.expire_critical_notifications` is true.
- [x] 5.4 Remove timed-out, FIFO-bumped, or stale popups without marking notifications read.
- [x] 5.5 Hide all visible popups when the notification panel opens and cancel their timers.
- [x] 5.6 Cancel all popup timers on widget disposal.

## 6. Popup Rendering and Integration

- [x] 6.1 Render the popup view as a transparent Flutter surface aligned top-right with popup cards stacked oldest at top and newest at bottom.
- [x] 6.2 Request showing the native popup window when at least one popup is visible and hiding it when none are visible.
- [x] 6.3 Use notification panel width for popup cards and keep card spacing/visual styling consistent with the notification panel.

## 7. Verification

- [x] 7.1 Add Flutter widget tests for popup ordering, max-four FIFO overflow, popup disabled behavior, and panel-open hiding.
- [x] 7.2 Add Flutter tests for rightward dismissal, body click mark-read, action click mark-read/invoke, close click dismissal, and timeout unread preservation.
- [x] 7.3 Add Flutter tests for critical popup expiration behavior with `expire_critical_notifications` true and false.
- [x] 7.4 Run relevant Rust and Flutter test suites and fix regressions.
