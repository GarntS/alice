## Context

Alice receives freedesktop notifications in `native/alice_platform`, stores their public snapshot payload plus store-only metadata, and emits `ActionInvoked` when Flutter reports an action click. The notification protocol does not identify a compositor toplevel, and the current action path has no window-activation step.

Alice already targets wlroots through GTK layer shell and ships `wayland-client` plus `wayland-protocols-wlr` in `native/alice_layer_shell`, but that crate currently opens only a short-lived connection for capability detection. Foreign-toplevel handles and `wl_seat` objects are connection-bound and must remain alive on the event queue that created them. A useful activation service therefore needs a persistent Wayland connection and event loop rather than per-click discovery.

`wlr-foreign-toplevel-management-unstable-v1` exposes event-driven toplevel handles with app ID, title, output, state, and lifecycle events. Its `activate(wl_seat)` request is compositor-generic across supporting wlroots compositors, but activation is advisory and identity matching remains Alice's responsibility.

## Goals / Non-Goals

**Goals:**
- Preserve notification origin identity needed to associate an action with an application toplevel.
- Maintain an event-driven cache of foreign-toplevel handles without polling or Sway IPC.
- Make a deterministic, best-effort activation request after delivering a notification action.
- Degrade to current action behavior on unsupported compositors, missing identities, ambiguous matches, closed handles, unavailable seats, or rejected requests.
- Keep compositor objects and internal notification metadata out of the public Flutter snapshot model.

**Non-Goals:**
- Portable activation on non-wlroots Wayland compositors.
- Sway IPC, `swaymsg`, title heuristics, PID-tree matching, or X11 activation fallbacks.
- Creating or launching an application when no matching toplevel exists.
- Selecting among several never-activated windows of the same application by notification content.
- Multi-seat routing based on the specific GTK input event; this change uses the first usable advertised seat.
- Changing dismiss, mark-read, popup-lifecycle, or notification-expiration behavior.

## Decisions

### Keep the tracker in `alice_platform` on a dedicated Wayland thread

Add a private foreign-toplevel module to `native/alice_platform`. At runtime startup it creates its own Wayland connection, binds the foreign-toplevel manager and an advertised `wl_seat`, and runs a blocking event loop on a dedicated thread. A channel carries activation commands into that thread so all handle access remains connection- and thread-local.

The tracker records each live handle's normalized app ID, title, current activated state, creation order, and last-activation sequence. Protocol callbacks update the records and remove closed handles. Idle operation is event-driven; no compositor-tree polling is introduced.

Alternative: extend `alice_layer_shell` and call it across Rust static-library or C FFI boundaries. Rejected because notification identity and action orchestration already live in `alice_platform`, while introducing a cross-static-library service would require broader linker/API restructuring. The separate connection is cheap and keeps Alice's own surface placement independent from foreign-window control.

Alternative: reconnect and enumerate on each click. Rejected because initial enumeration is asynchronous, adds latency, and creates races around handle discovery and closure.

### Use `desktop-entry` as the authoritative notification identity

Extend the store-only notification wrapper with an optional normalized desktop-entry identity parsed from the `desktop-entry` hint. Normalization trims whitespace, removes one case-insensitive `.desktop` suffix, and compares case-insensitively against normalized foreign-toplevel app IDs. The public `NotificationSnapshot` and FRB schema remain unchanged.

Do not fall back to notification `app_name`, summary, body, or toplevel title. Those values are presentation strings, can change, and are not trustworthy identifiers. If `desktop-entry` is absent or does not match exactly after normalization, activation is skipped while action delivery proceeds.

Alternative: query the D-Bus sender PID and match descendants. Rejected for this path because Electron and sandbox process trees often separate the notifying process from the window owner, while foreign-toplevel management does not expose PIDs.

### Resolve multiple matching toplevels conservatively

Candidate selection uses the following order:
1. If exactly one live handle matches, select it.
2. If multiple match and exactly one is currently activated, select it.
3. Otherwise, if one candidate has a unique greatest last-activation sequence observed by Alice, select it.
4. Otherwise treat the match as ambiguous and skip activation.

This favors the application's most recently used existing window without guessing from mutable titles. Closed handles are never candidates. Creation order is retained for diagnostics and deterministic tests, not as a final ambiguity-breaking heuristic.

Alternative: always choose the first or newest handle. Rejected because opening the wrong conversation window is more disruptive than preserving current no-focus behavior.

### Deliver the action before requesting activation

`invoke_action_impl` retrieves the notification's internal activation identity, emits and awaits the D-Bus `ActionInvoked` signal, and then sends a best-effort activation command to the tracker. Emission failure does not trigger activation, preserving the principle that activation accompanies a delivered user action. Once action emission succeeds, activation failure is logged diagnostically but is not returned to Flutter and does not alter notification read or popup state.

The activation worker resolves the identity against its current live records and invokes `activate(seat)` on the selected handle, then flushes the Wayland connection. This ordering gives the application the action before the compositor switches focus, while avoiding arbitrary sleeps or polling for app-side state changes.

Alternative: activate before `ActionInvoked`. Rejected because the application should receive the intent first and because focus must not substitute for failed action delivery.

### Treat protocol and compositor failures as optional capability loss

If Wayland connection setup, registry binding, manager support, or seat discovery fails, the tracker reports unavailable and exits or remains inert without stopping Alice's snapshot runtime. Runtime code retains a command sender only for a successfully initialized service. Handle closure and compositor rejection are normal best-effort outcomes.

Unit tests will isolate normalization and candidate selection from Wayland proxies. Protocol integration will use dispatch/state tests where practical and a manual Sway verification checklist for actual workspace switching.

## Risks / Trade-offs

- **`desktop-entry` and app ID differ for some applications** → Normalize conservatively and skip rather than use broad title heuristics; document this as best-effort behavior.
- **Multiple windows remain indistinguishable** → Use current/last activation state and fail closed when no unique candidate exists.
- **The protocol is unstable and not universal** → Bind only when advertised, cap the negotiated version, and preserve action delivery when unavailable.
- **A compositor may reject an activation request** → Treat activation as advisory and avoid surfacing it as an action error.
- **A handle can close between selection and request** → Keep selection and request on the event-loop thread and tolerate protocol lifecycle races.
- **The first advertised seat may not be the interacting seat on multi-seat systems** → Scope this change to the common single-seat case and leave event-seat propagation for a separate proposal.
- **A second Wayland connection duplicates a small amount of state** → Accept the negligible cost to avoid coupling the platform and layer-shell static libraries.

## Migration Plan

1. Add the tracker and unit-test its pure identity/candidate-selection logic while leaving activation disconnected.
2. Start the optional tracker with the native runtime and verify unsupported compositor startup remains unchanged.
3. Add store-only `desktop-entry` metadata and connect successful action emission to activation commands.
4. Verify on Sway with matching, missing, ambiguous, and closed-window cases.

The change has no persisted-data or public-API migration. Rollback removes the optional tracker and store-only metadata; existing `ActionInvoked` behavior remains the compatibility baseline.
