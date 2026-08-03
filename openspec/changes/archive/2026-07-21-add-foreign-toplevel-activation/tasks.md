## 1. Notification Identity

- [x] 1.1 Add store-only optional activation identity metadata to `StoredNotification` and parse the freedesktop `desktop-entry` hint without changing `NotificationSnapshot` or generated FRB shapes.
- [x] 1.2 Implement conservative identity normalization for desktop-entry values and foreign-toplevel app IDs, including whitespace, case, and a single `.desktop` suffix.
- [x] 1.3 Add Rust tests for present, absent, malformed, replacement, and snapshot-extraction cases, proving activation metadata remains internal while existing notification fields are preserved.

## 2. Foreign Toplevel Tracker

- [x] 2.1 Add the required Wayland client and wlroots protocol dependencies to `alice_platform` and create a private foreign-toplevel activation module.
- [x] 2.2 Implement optional startup on a dedicated thread, binding the advertised foreign-toplevel manager and first usable seat while allowing unsupported or failed initialization to leave Alice running normally.
- [x] 2.3 Implement event-loop command wakeup plus persistent tracking of live handles, app IDs, titles, activated state, closure, creation order, and last-activation sequence without compositor-tree polling.
- [x] 2.4 Implement pure candidate selection that chooses a sole match, uniquely active match, or unique most-recent match and rejects absent or unresolved ambiguous matches.
- [x] 2.5 Implement best-effort `activate(seat)` dispatch and connection flushing on the tracker thread, tolerating stale handles, unavailable seats, protocol errors, and compositor rejection.
- [x] 2.6 Add focused Rust tests for identity matching, state transitions, activation recency, ambiguity, closure removal, unsupported initialization, and activation command handling.

## 3. Notification Action Integration

- [x] 3.1 Start and retain the optional foreign-toplevel activation service from the native runtime without changing snapshot startup behavior when the service is unavailable.
- [x] 3.2 Update notification action invocation to retrieve the stored activation identity, await successful `ActionInvoked` emission, and only then enqueue the best-effort activation request.
- [x] 3.3 Preserve existing Flutter action, popup removal, mark-read, dismissal, and error behavior when identity resolution or activation fails.
- [x] 3.4 Add tests proving successful action emission precedes activation, failed action emission suppresses activation, and unsupported or ambiguous activation never suppresses action delivery.

## 4. Verification

- [x] 4.1 Run `cargo fmt --manifest-path native/Cargo.toml --all -- --check` and `cargo test --manifest-path native/Cargo.toml --workspace`.
- [x] 4.2 Run the focused Flutter notification tests to confirm no public snapshot or UI behavior regressed.
- [x] 4.3 Manually verify on Sway that a notification action with a matching desktop-entry switches to the existing application window, and verify missing, unmatched, ambiguous, and closed-window cases remain harmless.
- [x] 4.4 Run `openspec validate add-foreign-toplevel-activation --strict`.
