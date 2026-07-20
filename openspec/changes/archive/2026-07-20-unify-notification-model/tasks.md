## 1. Canonical Notification Payload

- [x] 1.1 In `native/alice_platform/src/notifications.rs`, replace local `Urgency` and `NotificationAction` with imports of `NotificationUrgency` and `NotificationActionSnapshot` from `state.rs`.
- [x] 1.2 Reshape `StoredNotification` into a thin internal record containing a `NotificationSnapshot` payload plus the existing `received_at: Instant` store-only metadata; do not add, remove, or expose snapshot fields.
- [x] 1.3 Update `NotificationServer::notify` hint/action parsing to construct the canonical snapshot types while preserving IDs, unread state, timestamps, image fields, and D-Bus behavior.

## 2. Store and Runtime Integration

- [x] 2.1 Update `NotificationStore::{add_or_replace,remove,get_all,mark_read}` to operate through the canonical payload and return cloned `NotificationSnapshot` values.
- [x] 2.2 Simplify `native/alice_platform/src/runtime.rs::notification_snapshots` to retrieve canonical payloads directly, removing field-by-field urgency/action conversion.
- [x] 2.3 Confirm `native/alice_platform/src/state.rs`, `api.rs`, generated FRB files, timeout calculation, D-Bus methods/signals, ordering, and image limits are unchanged.

## 3. Behavioral Tests

- [x] 3.1 Add Rust store/model tests covering add, same-id replacement, mark-read, remove, and exact snapshot extraction including action, urgency, timestamp, and image/path fields.
- [x] 3.2 Add or retain a test proving store-only `received_at` does not alter the public snapshot payload; do not introduce notification expiration assertions in this change.
- [x] 3.3 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform`.
- [x] 3.4 Run `flutter test test/notification_popup_state_test.dart test/notification_popups_test.dart`.
- [x] 3.5 Search active Rust source and require no local `enum Urgency` or `struct NotificationAction` duplicate and no field-by-field `notification_snapshots` mapper.
- [x] 3.6 Run `openspec validate unify-notification-model --strict`.
