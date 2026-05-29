## MODIFIED Requirements

### Requirement: StatusNotifierWatcher service
Alice SHALL host StatusNotifierWatcher services for the KDE and freedesktop bus names and interfaces, and Alice SHALL advertise itself as an active StatusNotifier host when those services start.

#### Scenario: Runtime starts tray watcher
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL register watcher objects at `/StatusNotifierWatcher`
- **AND** Alice SHALL request `org.kde.StatusNotifierWatcher` and `org.freedesktop.StatusNotifierWatcher` on the session bus
- **AND** Alice SHALL report `IsStatusNotifierHostRegistered` as true for the watcher interfaces
- **AND** Alice SHALL emit `StatusNotifierHostRegistered` for the watcher interfaces when it becomes the active host

### Requirement: Tray item registration
Alice SHALL accept tray item and host registration calls, emit registration signals when registration state changes, and trigger snapshot refreshes when registration state changes.

#### Scenario: Tray item registers
- **WHEN** a StatusNotifierItem registers by service or object path
- **THEN** Alice SHALL canonicalize the item id
- **AND** Alice SHALL add it to watcher state
- **AND** Alice SHALL emit `StatusNotifierItemRegistered` with the registered item id when it is newly added
- **AND** Alice SHALL trigger a snapshot rebuild when it is newly added

#### Scenario: Tray host registers
- **WHEN** a StatusNotifierHost registers and Alice does not already have a registered host
- **THEN** Alice SHALL mark a host as registered
- **AND** Alice SHALL emit `StatusNotifierHostRegistered`
- **AND** Alice SHALL trigger a snapshot rebuild
