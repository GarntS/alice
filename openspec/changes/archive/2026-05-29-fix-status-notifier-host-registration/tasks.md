## 1. Watcher State and Signals

- [x] 1.1 Refactor tray watcher registration helpers so host and item state transitions can report whether state changed and which canonical item id changed.
- [x] 1.2 Add host self-registration during StatusNotifierWatcher startup after watcher objects and bus names are established.
- [x] 1.3 Emit `StatusNotifierHostRegistered` when host registration transitions from false to true.
- [x] 1.4 Emit `StatusNotifierItemRegistered` when `RegisterStatusNotifierItem` adds a new canonical item id.

## 2. Runtime Behavior Preservation

- [x] 2.1 Preserve existing snapshot trigger behavior for new item registration and host registration state changes.
- [x] 2.2 Preserve existing KDE and freedesktop watcher object paths, bus names, properties, and method compatibility.
- [x] 2.3 Ensure duplicate item or host registration calls do not produce duplicate state changes or unnecessary snapshot refreshes.

## 3. Verification

- [x] 3.1 Add or update Rust tests for canonical item registration and host registration state transitions where feasible.
- [x] 3.2 Run native/Flutter test coverage relevant to tray snapshots and top-bar tray rendering.
- [x] 3.3 Manually validate that `IsStatusNotifierHostRegistered` is true after Alice startup and that TIDAL Hi-Fi registers/displays its tray icon after restart without manual D-Bus calls.
