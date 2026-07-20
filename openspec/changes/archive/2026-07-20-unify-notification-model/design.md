## Context

`notifications.rs` stores `StoredNotification` fields using local `Urgency` and `NotificationAction` types. `runtime.rs::notification_snapshots` clones the store and maps every field to the equivalent `state.rs` snapshot types. `StoredNotification::received_at: Instant` is store-only and currently unread; the configured expiry timeout is computed but not acted upon.

## Goals / Non-Goals

**Goals:**
- Make `NotificationSnapshot`, `NotificationUrgency`, and `NotificationActionSnapshot` the canonical payload types.
- Keep only a thin internal record for truly store-only metadata.
- Preserve store mutation and D-Bus/FRB semantics.

**Non-Goals:**
- Implementing, removing, or redefining notification expiration.
- Changing public snapshot fields, generated bindings, IDs, ordering, image processing, hints, D-Bus methods, capabilities, or signals.
- Changing popup expiration, which is a separate Dart concern.

## Decisions

### Store a canonical snapshot payload inside a thin record

Replace the field-parallel `StoredNotification` with an internal record conceptually shaped as:

```rust
struct StoredNotification {
    snapshot: NotificationSnapshot,
    received_at: Instant,
}
```

Retain `received_at` unchanged because deleting it would pre-decide the unresolved native-expiry work. The wrapper earns its cost as an internal metadata boundary; local urgency/action enums do not.

Alternative: store `NotificationSnapshot` directly. Rejected for this change because it would discard monotonic receipt metadata before timeout behavior is decided.

### Move store operations through the payload

`add_or_replace`, `remove`, and `mark_read` use `record.snapshot.id` / `record.snapshot.is_read`. Snapshot extraction returns cloned payloads directly. `NotificationServer::notify` constructs canonical action/urgency types at the D-Bus boundary.

### Keep runtime aggregation shape stable

Replace `runtime.rs::notification_snapshots` field mapping with a direct call returning `Vec<NotificationSnapshot>`. Do not modify `BarSnapshot`, `api.rs`, `state.rs` public definitions, or generated files.

## Risks / Trade-offs

- **Image bytes are still cloned for snapshots** → Preserve existing ownership/FRB behavior; optimizing byte transport is outside scope.
- **Expiry work later needs more metadata** → The thin internal record remains the extension point.
- **Accidental behavior change during field movement** → Add focused store tests and retain all field values in receipt/replacement assertions.

## Migration Plan

This is in-memory state only. Replace types and conversion atomically, run Rust and focused Dart tests, and roll back as one change if schema compatibility fails.

## Open Questions

Native notification expiration remains unresolved and must be proposed separately.
