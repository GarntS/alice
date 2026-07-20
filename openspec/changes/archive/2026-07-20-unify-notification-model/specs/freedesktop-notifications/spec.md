## MODIFIED Requirements

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
