## MODIFIED Requirements

### Requirement: Tray icon resolution and caching
Alice SHALL resolve tray icons from SNI pixmaps, absolute PNG paths, or icon names, cache unchanged snapshots between reads, and refresh affected data when published item properties change.

#### Scenario: IconPixmap is available
- **WHEN** an item exposes valid IconPixmap data
- **THEN** Alice SHALL convert ARGB pixmap data to PNG bytes
- **AND** Alice SHALL scale icons to 16x16 pixels when needed

#### Scenario: Icon name is available
- **WHEN** pixmap data is unavailable and an icon theme name can be resolved
- **THEN** Alice SHALL look up PNG icons from item icon theme paths, XDG icon directories, or pixmaps fallback directories

#### Scenario: Absolute icon path is available
- **WHEN** pixmap data is unavailable and IconName is an absolute path to a readable PNG
- **THEN** Alice SHALL load that exact path without adding an extension
- **AND** Alice SHALL scale the image to 16x16 pixels when needed

#### Scenario: Icon data is unavailable or malformed
- **WHEN** supplied artwork cannot be read or decoded
- **THEN** Alice SHALL retain a usable tray item with fallback artwork
- **AND** Alice SHALL retry missing artwork within a bounded interval while the item remains registered

#### Scenario: Published item data changes
- **WHEN** an item emits NewIcon, NewAttentionIcon, NewIconThemePath, NewTitle, NewStatus, or relevant PropertiesChanged
- **THEN** Alice SHALL refresh affected icon, label, status, and action metadata without requiring re-registration
- **AND** unrelated unchanged tray items SHALL retain their cached data

#### Scenario: Item disappears
- **WHEN** an item's service disappears or its registration is removed
- **THEN** Alice SHALL discard its cached data and subscriptions

### Requirement: Tray actions
Alice SHALL route tray actions over a verified KDE or freedesktop StatusNotifierItem interface, observe remote results, and support menu fallback without binding middle-click.

#### Scenario: Tray item is left-clicked
- **WHEN** a user left-clicks a tray item on the bar or in overflow
- **THEN** Alice SHALL invoke Activate with available screen coordinates unless the item declares ItemIsMenu
- **AND** Alice SHALL open the published menu instead when the item declares ItemIsMenu or Activate is unsupported

#### Scenario: Tray item is right-clicked
- **WHEN** a user right-clicks a tray item on the bar or in overflow
- **THEN** Alice SHALL open its usable published menu
- **AND** if no usable published menu exists Alice SHALL invoke ContextMenu only when supported

#### Scenario: Tray item is clicked
- **WHEN** Flutter requests activate, secondaryActivate, or contextMenu directly
- **THEN** Rust SHALL invoke the corresponding supported SNI method with x/y coordinates and await its reply with a bounded timeout

#### Scenario: Preferred interface is unavailable
- **WHEN** an item supports only the freedesktop interface
- **THEN** Alice SHALL read properties and send actions through that verified interface rather than assuming KDE support from proxy construction

#### Scenario: Remote action fails
- **WHEN** an action returns an error or times out
- **THEN** Alice SHALL record the destination, interface, method, and failure reason in diagnostics
- **AND** Alice SHALL NOT report successful execution merely because a message was dispatched
- **AND** Alice SHALL NOT retry a potentially executed action on another interface after a timeout or general remote error
- **AND** Alice SHALL NOT produce a user-facing failure notification

#### Scenario: Unsupported activation has no menu fallback
- **WHEN** Activate is unsupported and no usable menu exists
- **THEN** Alice SHALL leave the bar usable and record the unsupported action in diagnostics

#### Scenario: Middle-click is received
- **WHEN** a user middle-clicks a tray item
- **THEN** Alice SHALL NOT dispatch a tray action for that click
