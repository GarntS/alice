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
Alice SHALL store received notifications in memory and expose them through `BarSnapshot.notifications`.

#### Scenario: Notify call is received
- **WHEN** an application calls `Notify`
- **THEN** Alice SHALL parse app name, app icon, summary, body, actions, urgency, category, image data, and image path where present
- **AND** Alice SHALL allocate or reuse an id according to `replaces_id`
- **AND** Alice SHALL mark the stored notification unread
- **AND** Alice SHALL trigger a snapshot rebuild

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
Alice SHALL support dismissing one notification, dismissing all notifications, marking notifications read, and invoking notification actions from notification panel and popup UI surfaces.

#### Scenario: Notification is dismissed by user
- **WHEN** Flutter requests dismissal of a notification id
- **THEN** Alice SHALL remove it from the store
- **AND** Alice SHALL emit `NotificationClosed` with reason 2 when possible
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Notification action is invoked
- **WHEN** Flutter invokes a notification action key
- **THEN** Alice SHALL emit `ActionInvoked` for that notification id and action key when possible

#### Scenario: Notification is marked read by user interaction
- **WHEN** Flutter requests marking a notification id read from the notification panel or popup UI
- **THEN** Alice SHALL mark that notification read in the store when it exists
- **AND** Alice SHALL trigger a snapshot rebuild
