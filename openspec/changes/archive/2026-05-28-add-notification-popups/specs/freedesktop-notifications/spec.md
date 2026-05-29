## MODIFIED Requirements

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
