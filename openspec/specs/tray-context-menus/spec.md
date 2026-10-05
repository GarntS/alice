# Tray Context Menus Specification

## Purpose

Expose application-published tray menus as accessible context menus with reliable action dispatch and popup lifecycle management.

## Requirements

### Requirement: Published menu presentation
Alice SHALL consume the tray item's Menu object through com.canonical.dbusmenu and present its current tree, including labels, separators, nested submenus, visibility, enabled states, and check/radio states.

#### Scenario: Menu is opened
- **WHEN** a tray menu is requested
- **THEN** Alice SHALL prepare the menu through AboutToShow when supported and retrieve its layout
- **AND** Alice SHALL display visible entries in published order with their enabled and toggle states

#### Scenario: Submenu is opened
- **WHEN** the user opens a nested submenu
- **THEN** Alice SHALL prepare and display its current children without clipping them outside the popup surface

#### Scenario: Menu changes while open
- **WHEN** LayoutUpdated or ItemsPropertiesUpdated changes the published menu
- **THEN** Alice SHALL update the displayed tree and states
- **AND** stale or removed entries SHALL NOT remain actionable

### Requirement: Menu action dispatch
Alice SHALL dispatch application menu selections as D-Bus menu events, preserving item identifiers and observing failure results.

#### Scenario: Enabled menu entry is selected
- **WHEN** the user selects a visible enabled application menu entry
- **THEN** Alice SHALL send its clicked Event with the entry id, protocol-compatible payload, and timestamp
- **AND** Alice SHALL dismiss the menu after dispatching the selection

#### Scenario: Disabled or hidden entry is targeted
- **WHEN** an entry is disabled, hidden, or no longer present
- **THEN** Alice SHALL NOT dispatch an activation event for that entry

#### Scenario: Dispatch fails
- **WHEN** a menu event fails or times out
- **THEN** Alice SHALL record diagnostic context without a user-facing notification or automatic duplicate dispatch

### Requirement: Secondary action entry
Alice SHALL prepend a synthetic Secondary action entry when the item supports SecondaryActivate, separated from application entries and distinct from application menu identifiers.

#### Scenario: Secondary activation is supported
- **WHEN** an item's menu is opened and SecondaryActivate is supported
- **THEN** Alice SHALL show Secondary action as the first entry
- **AND** selecting it SHALL invoke SecondaryActivate rather than a D-Bus menu Event

#### Scenario: Secondary activation is unsupported
- **WHEN** an item's menu is opened and SecondaryActivate is unsupported
- **THEN** Alice SHALL omit the synthetic Secondary action entry

### Requirement: Tray menu popup lifecycle
Alice SHALL present tray menus in a dedicated, conventionally styled context-menu popup anchored to the selected tray item, using the existing single-popup policy.

#### Scenario: Menu opens from a tray item
- **WHEN** the menu opens from the bar or overflow panel
- **THEN** Alice SHALL close the previously open panel or tray menu
- **AND** Alice SHALL position the menu on the originating monitor within usable screen bounds
- **AND** the menu SHALL not be constrained to the bar's short drawing surface

#### Scenario: User navigates or dismisses the menu
- **WHEN** a menu is open
- **THEN** Alice SHALL support pointer interaction and keyboard navigation, including submenu navigation and activation
- **AND** Escape or a click outside SHALL dismiss the menu and release its input surface

#### Scenario: Source disappears or request is superseded
- **WHEN** the item's service disappears or a newer popup request supersedes a pending menu load
- **THEN** Alice SHALL discard obsolete results, dismiss any obsolete menu, and release associated subscriptions

#### Scenario: Menu cannot be loaded
- **WHEN** the published menu is unavailable or malformed
- **THEN** Alice SHALL record the failure, avoid leaving an empty input-blocking popup, and preserve usable bar interactions
