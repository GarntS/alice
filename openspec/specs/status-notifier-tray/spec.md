# Status Notifier Tray Specification

## Purpose
Define implemented StatusNotifier tray watcher hosting, tray item snapshots, icon handling, overflow UI, and tray item actions.
## Requirements
### Requirement: StatusNotifierWatcher service
Alice SHALL host StatusNotifierWatcher services for the KDE and freedesktop bus names and interfaces, and Alice SHALL advertise itself as an active StatusNotifier host when those services start.

#### Scenario: Runtime starts tray watcher
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL register watcher objects at `/StatusNotifierWatcher`
- **AND** Alice SHALL request `org.kde.StatusNotifierWatcher` and `org.freedesktop.StatusNotifierWatcher` on the session bus
- **AND** Alice SHALL report `IsStatusNotifierHostRegistered` as true for the watcher interfaces
- **AND** Alice SHALL emit `StatusNotifierHostRegistered` for the watcher interfaces when it becomes the active host

### Requirement: Tray item registration
Alice SHALL accept tray item and host registration calls, emit registration signals when registration state changes, and trigger snapshot refreshes when registration state changes. Registration input and watcher-property input SHALL share one semantic parser for StatusNotifier item service names and object paths, and canonical watcher IDs SHALL be derived from that parsed value.

#### Scenario: Tray item registers by service name
- **WHEN** a StatusNotifierItem registers with a non-empty service name and no object path
- **THEN** Alice SHALL parse that service name with the shared identifier parser
- **AND** Alice SHALL use `/StatusNotifierItem` as its object path
- **AND** Alice SHALL emit the same canonical registered item id as before this refactor

#### Scenario: Tray item registers by object path
- **WHEN** a StatusNotifierItem registers with an object path and the D-Bus sender is available
- **THEN** Alice SHALL parse the sender as the service name and the supplied path as the object path
- **AND** Alice SHALL derive the canonical registered item id from those parsed fields

#### Scenario: Watcher registration property is read
- **WHEN** Alice reads a service-only or service-plus-path identifier from `RegisteredStatusNotifierItems`
- **THEN** Alice SHALL use the same parser used by registration
- **AND** the resulting service name and object path SHALL match registration canonicalization

#### Scenario: Tray item registers
- **WHEN** a parsed canonical item id is newly added
- **THEN** Alice SHALL add it to watcher state
- **AND** Alice SHALL emit `StatusNotifierItemRegistered` with that id
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Tray host registers
- **WHEN** a StatusNotifierHost registers and Alice does not already have a registered host
- **THEN** Alice SHALL mark a host as registered
- **AND** Alice SHALL emit `StatusNotifierHostRegistered`
- **AND** Alice SHALL trigger a snapshot rebuild

### Requirement: Tray item snapshots
Alice SHALL read registered tray items into `TrayItemSnapshot` values.

#### Scenario: Tray item is readable
- **WHEN** Alice reads a tray item
- **THEN** it SHALL populate id, label, service name, object path, and optional PNG icon bytes
- **AND** the label SHALL prefer title, then humanized item id or process name, then simplified bus name

### Requirement: Tray icon resolution and caching
Alice SHALL resolve tray icons from SNI pixmaps or icon names and cache snapshots between reads.

#### Scenario: IconPixmap is available
- **WHEN** an item exposes `IconPixmap`
- **THEN** Alice SHALL convert ARGB pixmap data to PNG bytes
- **AND** Alice SHALL scale icons to 16x16 pixels when needed

#### Scenario: Icon name is available
- **WHEN** pixmap data is unavailable and an icon name can be resolved
- **THEN** Alice SHALL look up PNG icons from item icon theme paths, XDG icon directories, or pixmaps fallback directories

### Requirement: Tray bar visibility and overflow
Alice SHALL show at most the configured tray item budget on the bar and expose remaining items through an overflow panel.

#### Scenario: Tray items exceed configured visible count
- **WHEN** tray item count exceeds the visible budget
- **THEN** Alice SHALL show visible tray icons on the bar
- **AND** Alice SHALL show an overflow pill with the number of remaining items
- **AND** the overflow panel SHALL list the remaining tray items

### Requirement: Tray actions
Alice SHALL route tray item activation requests back to the StatusNotifierItem over D-Bus.

#### Scenario: Tray item is clicked
- **WHEN** Flutter sends `activate`, `secondaryActivate`, or `contextMenu` for a tray item
- **THEN** Rust SHALL call the corresponding SNI method with x/y coordinates on an available KDE or freedesktop item interface

