## Why

Alice currently owns the StatusNotifierWatcher bus names, but reports no registered tray host on startup. Some StatusNotifier/AppIndicator clients, observed with TIDAL Hi-Fi, do not publish tray items until a host is registered, leaving Alice's tray empty even though tray-capable apps are running.

## What Changes

- Make Alice announce itself as an active StatusNotifier host when the tray watcher starts.
- Emit the expected StatusNotifier host registration signal when Alice becomes the host.
- Emit item registration signals when new tray items register with Alice's watcher.
- Preserve existing watcher names, item canonicalization, snapshot refresh triggers, icon resolution, tray overflow UI, and tray action routing.

## Capabilities

### New Capabilities

### Modified Capabilities
- `status-notifier-tray`: Tighten StatusNotifierWatcher host behavior so Alice advertises an active host and emits registration signals expected by tray clients.

## Impact

- Affected Rust module: `native/alice_platform/src/tray.rs`.
- Affected runtime behavior: session-bus StatusNotifierWatcher startup and D-Bus signals.
- Affected tests/specs: StatusNotifier tray requirements and Rust unit coverage for watcher startup/registration behavior where feasible.
- No breaking changes to Flutter APIs, platform channels, or user configuration.
