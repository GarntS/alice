## Why

Notifications are represented twice—once in the D-Bus store and again in the FRB snapshot model—with a field-by-field conversion on every bar snapshot. A snapshot-compatible stored payload removes this drift boundary while retaining a thin internal wrapper only for genuinely store-only metadata.

## What Changes

- Replace the duplicate internal `Urgency` and `NotificationAction` types with `NotificationUrgency` and `NotificationActionSnapshot`.
- Make each stored notification contain a `NotificationSnapshot` payload directly, with only a thin wrapper for store-only metadata such as the existing monotonic receipt time if it must be retained.
- Simplify `runtime.rs::notification_snapshots` to retrieve snapshot payloads without field-by-field remapping.
- Add store/model tests for receipt, replacement, read state, dismissal, and snapshot extraction.
- Do not implement or remove notification expiry behavior in this change; the currently computed-but-unused timeout remains a separately tracked correctness decision.

## Capabilities

### New Capabilities

### Modified Capabilities
- `freedesktop-notifications`: Require one snapshot-compatible notification payload across receipt, in-memory storage, and `BarSnapshot` exposure while preserving D-Bus and FRB behavior.

## Impact

- Affected implementation: `native/alice_platform/src/notifications.rs`, `native/alice_platform/src/runtime.rs`; `native/alice_platform/src/state.rs` supplies the existing canonical types but its public shapes must not change.
- Public API: no generated binding, field, enum, D-Bus method, signal, or status change.
- Tests: new Rust store/model tests plus existing Rust and relevant Dart notification tests.
- Explicit non-goal: notification expiration scheduling and timeout semantics.
