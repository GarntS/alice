## ADDED Requirements

### Requirement: Unified popup visibility change signaling
`NotificationPopupState` SHALL expose a standard Flutter listenable signal for popup visibility events so application projection and native popup-window synchronization use one registered state listener.

#### Scenario: Snapshot changes popup visibility
- **WHEN** snapshot processing adds, replaces, bumps, or removes one or more visible popups
- **THEN** `NotificationPopupState` SHALL emit exactly one listenable notification for that processing operation
- **AND** the application listener SHALL update the visible popup projection and synchronize the popup window

#### Scenario: User operation removes a popup
- **WHEN** a visible popup is removed by a popup drag, close action, notification action, or notification-panel opening
- **THEN** `NotificationPopupState` SHALL emit one listenable notification for the visibility change
- **AND** the application SHALL NOT require the initiating handler to repeat popup projection or window synchronization calls

#### Scenario: Popup expires
- **WHEN** an eligible popup timer expires and removes a visible popup
- **THEN** `NotificationPopupState` SHALL emit through the same listenable path used by synchronous mutations
- **AND** existing expiration and read-state semantics SHALL remain unchanged

#### Scenario: Popup operation is a no-op
- **WHEN** removal targets an ID that is not visible, hide-all runs with no visible popups, or snapshot processing produces no popup visibility event
- **THEN** `NotificationPopupState` SHALL NOT emit a listenable notification
- **AND** the application SHALL NOT perform duplicate popup-window synchronization for that operation

#### Scenario: Visible notification content changes without ID changes
- **WHEN** snapshot ingestion changes the content of a currently visible notification without changing its popup ID sequence
- **THEN** `AliceSnapshotState` SHALL refresh the popup notification projection from the new notification content
- **AND** the popup widget SHALL receive the changed content without requiring an ID visibility change
