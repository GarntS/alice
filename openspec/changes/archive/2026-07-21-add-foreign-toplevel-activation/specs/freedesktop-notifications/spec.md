## ADDED Requirements

### Requirement: Notification activation identity
Alice SHALL preserve the `desktop-entry` notification hint as internal origin metadata for best-effort application-window activation without adding it or compositor objects to the public notification snapshot.

#### Scenario: Desktop-entry hint is present
- **WHEN** an application sends a notification with a `desktop-entry` hint
- **THEN** Alice SHALL retain a normalized desktop-entry identity with the stored notification
- **AND** Alice SHALL leave the public `NotificationSnapshot` shape unchanged

#### Scenario: Desktop-entry hint is absent or invalid
- **WHEN** an application sends a notification without a usable `desktop-entry` hint
- **THEN** Alice SHALL store the notification normally without an activation identity

## MODIFIED Requirements

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
