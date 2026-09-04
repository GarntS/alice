## ADDED Requirements

### Requirement: Internally generated notification receipt
Alice SHALL admit internally generated calendar notifications to the same retained notification store and popup/snapshot behavior used for D-Bus notification receipt.

#### Scenario: Calendar runtime creates a notification
- **WHEN** a calendar alarm or reminder becomes due
- **THEN** Alice SHALL store it as an unread notification using the canonical notification payload
- **AND** Alice SHALL trigger a snapshot rebuild
- **AND** it SHALL be available to the existing notification panel and popup UI
