# Notification Popups Specification

## Purpose
Define Alice's notification popup surface, ordering, card behavior, dismissal semantics, expiration, and interaction with the notification panel.
## Requirements
### Requirement: Popup window placement
Alice SHALL render notification popups in a transparent floating surface anchored to the top-right of the screen.

#### Scenario: Popup surface is shown
- **WHEN** one or more notification popups are visible
- **THEN** Alice SHALL show them in a transparent non-exclusive floating surface
- **AND** Alice SHALL position the surface flush with the top-right screen edges so card padding provides equal top and right margins
- **AND** Alice SHALL use the notification panel width for the popup surface
- **AND** Alice SHALL size the popup surface tall enough to extend to the bottom of the display

### Requirement: Popup creation and ordering
Alice SHALL show newly received or replaced notifications as popup cards when notification popups are enabled.

#### Scenario: Notification is received while popups are enabled
- **WHEN** a new notification appears in `BarSnapshot.notifications` and `notifications.show_notification_popup` is `true`
- **THEN** Alice SHALL add a popup for that notification
- **AND** Alice SHALL display visible popups oldest at the top and newest at the bottom

#### Scenario: Notification replaces an existing notification
- **WHEN** a notification update replaces an existing notification id
- **THEN** Alice SHALL treat the replacement as a popup event
- **AND** Alice SHALL reset that popup's display timer

#### Scenario: Popups are disabled
- **WHEN** a new or replaced notification appears and `notifications.show_notification_popup` is `false`
- **THEN** Alice SHALL NOT show a popup for that notification
- **AND** Alice SHALL keep the notification in the notification list according to normal storage behavior

### Requirement: Popup visible limit
Alice SHALL display at most four notification popups at once.

#### Scenario: Fifth popup arrives
- **WHEN** four notification popups are already visible and another notification popup is added
- **THEN** Alice SHALL remove the oldest visible popup from the popup surface
- **AND** Alice SHALL show the new popup as the newest visible popup
- **AND** Alice SHALL leave the bumped notification in the notification list with its existing read state

### Requirement: Popup card content and actions
Alice SHALL render notification popup cards with the same core content and action affordances as notification panel cards.

#### Scenario: Popup card renders a notification
- **WHEN** a notification popup is visible
- **THEN** Alice SHALL show the app name, icon or fallback icon, received time, summary, body, and actions where present
- **AND** Alice SHALL provide a close affordance matching the notification panel card close behavior

#### Scenario: Popup action is clicked
- **WHEN** the user clicks an action button on a notification popup
- **THEN** Alice SHALL invoke the notification action for that notification id and action key when possible
- **AND** Alice SHALL mark the notification read
- **AND** Alice SHALL remove the popup from view
- **AND** Alice SHALL keep the notification in the notification list unless the originating action causes it to be closed separately

### Requirement: Popup dismissal semantics
Alice SHALL distinguish popup-only removal from notification deletion.

#### Scenario: Popup is dragged right
- **WHEN** the user dismisses a popup by dragging it to the right
- **THEN** Alice SHALL remove that popup from view
- **AND** Alice SHALL mark the notification read
- **AND** Alice SHALL keep the notification in the notification list

#### Scenario: Popup body is clicked
- **WHEN** the user clicks the body of a popup card
- **THEN** Alice SHALL mark the notification read
- **AND** Alice SHALL keep the popup visible unless another popup removal rule applies

#### Scenario: Popup close button is clicked
- **WHEN** the user clicks the close button on a popup card
- **THEN** Alice SHALL dismiss/delete the notification using the same semantics as the notification panel card close button
- **AND** Alice SHALL remove the popup from view

### Requirement: Popup expiration
Alice SHALL remove eligible popup cards after the configured display time without marking their notifications read.

#### Scenario: Non-critical popup reaches display time
- **WHEN** a non-critical popup has been visible for `notifications.notification_display_time_ms`
- **THEN** Alice SHALL remove the popup from view
- **AND** Alice SHALL leave the notification in the notification list unread unless it was already read

#### Scenario: Display time is zero
- **WHEN** `notifications.notification_display_time_ms` is `0`
- **THEN** Alice SHALL NOT auto-expire notification popups by display time

#### Scenario: Critical popup expiration is disabled
- **WHEN** a critical notification popup is visible and `notifications.expire_critical_notifications` is `false`
- **THEN** Alice SHALL NOT auto-expire that popup by display time
- **AND** Alice SHALL keep it visible until dragged right, closed, removed by FIFO overflow, removed because the notification no longer exists, or hidden because the notification panel opens

#### Scenario: Critical popup expiration is enabled
- **WHEN** a critical notification popup is visible and `notifications.expire_critical_notifications` is `true`
- **THEN** Alice SHALL apply `notifications.notification_display_time_ms` to that popup as normal

### Requirement: Popup lifecycle with notification panel
Alice SHALL hide visible popups when the notification panel opens.

#### Scenario: Notification panel opens
- **WHEN** the notification panel opens
- **THEN** Alice SHALL remove all visible notification popups from view
- **AND** Alice SHALL preserve the notification panel's existing behavior for marking notifications read

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

