# Freedesktop Notifications Specification

## Purpose
Define Alice's implemented freedesktop notification server, notification snapshots, unread badge, panel UI, and user actions.
## Requirements
### Requirement: Notification server registration
Alice SHALL host `org.freedesktop.Notifications` on the D-Bus session bus.

#### Scenario: Snapshot runtime starts
- **WHEN** the notification server task starts
- **THEN** Alice SHALL register an object at `/org/freedesktop/Notifications`
- **AND** Alice SHALL request the `org.freedesktop.Notifications` bus name
- **AND** Alice SHALL report server information for Alice and spec version `1.2`

### Requirement: Notification receipt and storage
Alice SHALL store received notifications in memory using one payload model compatible with `NotificationSnapshot` and SHALL expose those payloads through `BarSnapshot.notifications` without a second field-parallel notification representation. Alice MAY wrap the payload with internal store-only metadata that is not exposed over FRB.

#### Scenario: Notify call is received
- **WHEN** an application calls `Notify`
- **THEN** Alice SHALL parse app name, app icon, summary, body, actions, urgency, category, image data, and image path where present directly into the canonical snapshot-compatible payload
- **AND** Alice SHALL allocate or reuse an id according to `replaces_id`
- **AND** Alice SHALL mark the stored notification unread
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Stored notifications enter a bar snapshot
- **WHEN** Alice assembles `BarSnapshot.notifications`
- **THEN** Alice SHALL preserve every existing notification field and enum value
- **AND** Alice SHALL retrieve the canonical snapshot-compatible payload without field-by-field conversion from duplicate action or urgency types

#### Scenario: Store-only receipt metadata is retained
- **WHEN** the implementation requires monotonic receipt metadata for future native lifecycle behavior
- **THEN** Alice SHALL keep that metadata outside the public `NotificationSnapshot` payload
- **AND** this change SHALL NOT alter current notification expiration behavior

### Requirement: Notification hints and images
Alice SHALL parse implemented notification hints into snapshot fields.

#### Scenario: Hints are present
- **WHEN** `urgency`, `category`, `image-path`, `image_path`, `image-data`, or `icon_data` hints are provided
- **THEN** Alice SHALL map urgency to low, normal, or critical
- **AND** Alice SHALL preserve category and image paths
- **AND** Alice SHALL encode raw image-data buffers to PNG bytes when possible

### Requirement: Notification bar badge
Alice SHALL show a notification bar module with an unread indicator when unread notifications exist.

#### Scenario: Unread notifications exist
- **WHEN** at least one notification snapshot has `is_read` false
- **THEN** Alice SHALL show a badge dot on the notification bar pill

### Requirement: Notification panel
Alice SHALL render notifications in a dedicated panel sorted newest first.

#### Scenario: Panel opens with notifications
- **WHEN** the notifications panel renders stored notifications
- **THEN** Alice SHALL show app name, icon or fallback icon, received time, summary, body, and actions where present
- **AND** Alice SHALL provide clear-all and per-notification dismiss affordances
- **AND** Alice SHALL mark unread notifications as read after the panel opens

### Requirement: Notification user actions
Alice SHALL support dismissing one notification, dismissing all notifications, marking notifications read, and invoking notification actions from notification panel and popup UI surfaces. After successfully delivering a notification action, Alice SHALL make a best-effort request to activate a uniquely matched originating toplevel when foreign-toplevel activation is available.

#### Scenario: Notification is dismissed by user
- **WHEN** Flutter requests dismissal of a notification id
- **THEN** Alice SHALL remove it from the store
- **AND** Alice SHALL emit `NotificationClosed` with reason 2 when possible
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Notification action is invoked
- **WHEN** Flutter invokes a notification action key
- **THEN** Alice SHALL emit `ActionInvoked` for that notification id and action key when possible

#### Scenario: Notification action is invoked with a matched toplevel
- **WHEN** Flutter invokes a notification action key and the stored notification resolves to a unique foreign toplevel
- **THEN** Alice SHALL emit `ActionInvoked` for that notification id and action key when possible
- **AND** after successful action emission Alice SHALL request activation of the matched toplevel

#### Scenario: Notification action has no activation target
- **WHEN** Flutter invokes a notification action key and foreign-toplevel activation is unavailable or no unique target can be resolved
- **THEN** Alice SHALL emit `ActionInvoked` for that notification id and action key when possible
- **AND** Alice SHALL NOT treat the absence of activation as an action-delivery failure

#### Scenario: Action emission fails
- **WHEN** Alice cannot emit `ActionInvoked` for the requested notification action
- **THEN** Alice SHALL NOT request foreign-toplevel activation for that action

#### Scenario: Activation request fails
- **WHEN** `ActionInvoked` is emitted and the subsequent foreign-toplevel activation request fails or is not honored
- **THEN** Alice SHALL preserve successful action-delivery behavior

#### Scenario: Notification is marked read by user interaction
- **WHEN** Flutter requests marking a notification id read from the notification panel or popup UI
- **THEN** Alice SHALL mark that notification read in the store when it exists
- **AND** Alice SHALL trigger a snapshot rebuild

### Requirement: Notification activation identity
Alice SHALL preserve the `desktop-entry` notification hint as internal origin metadata for best-effort application-window activation without adding it or compositor objects to the public notification snapshot.

#### Scenario: Desktop-entry hint is present
- **WHEN** an application sends a notification with a `desktop-entry` hint
- **THEN** Alice SHALL retain a normalized desktop-entry identity with the stored notification
- **AND** Alice SHALL leave the public `NotificationSnapshot` shape unchanged

#### Scenario: Desktop-entry hint is absent or invalid
- **WHEN** an application sends a notification without a usable `desktop-entry` hint
- **THEN** Alice SHALL store the notification normally without an activation identity

### Requirement: Internally generated notification receipt
Alice SHALL admit internally generated calendar notifications to the same retained notification store and popup/snapshot behavior used for D-Bus notification receipt.

#### Scenario: Calendar runtime creates a notification
- **WHEN** a calendar alarm or reminder becomes due
- **THEN** Alice SHALL store it as an unread notification using the canonical notification payload
- **AND** Alice SHALL trigger a snapshot rebuild
- **AND** it SHALL be available to the existing notification panel and popup UI

