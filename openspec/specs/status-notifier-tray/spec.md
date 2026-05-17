# Status Notifier Tray Specification

## Purpose
Define implemented StatusNotifier tray watcher hosting, tray item snapshots, icon handling, overflow UI, and tray item actions.

## Requirements

### Requirement: StatusNotifierWatcher service
Alice SHALL host StatusNotifierWatcher services for the KDE and freedesktop bus names and interfaces.

#### Scenario: Runtime starts tray watcher
- **WHEN** the snapshot runtime starts
- **THEN** Alice SHALL register watcher objects at `/StatusNotifierWatcher`
- **AND** Alice SHALL request `org.kde.StatusNotifierWatcher` and `org.freedesktop.StatusNotifierWatcher` on the session bus

### Requirement: Tray item registration
Alice SHALL accept tray item and host registration calls and trigger snapshot refreshes when registration state changes.

#### Scenario: Tray item registers
- **WHEN** a StatusNotifierItem registers by service or object path
- **THEN** Alice SHALL canonicalize the item id
- **AND** Alice SHALL add it to watcher state
- **AND** Alice SHALL trigger a snapshot rebuild when it is newly added

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
