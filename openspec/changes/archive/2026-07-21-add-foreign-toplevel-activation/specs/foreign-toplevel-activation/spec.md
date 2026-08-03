## ADDED Requirements

### Requirement: Foreign toplevel discovery
Alice SHALL maintain an event-driven view of live application toplevels when the compositor advertises `wlr-foreign-toplevel-management-unstable-v1`.

#### Scenario: Supported compositor advertises existing and new toplevels
- **WHEN** Alice connects to a compositor that advertises foreign-toplevel management
- **THEN** Alice SHALL track the app ID, title, activation state, and lifecycle of each advertised toplevel
- **AND** Alice SHALL update tracking from compositor events without polling the compositor tree

#### Scenario: A tracked toplevel closes
- **WHEN** the compositor reports that a foreign toplevel has closed
- **THEN** Alice SHALL remove that toplevel from activation candidates

#### Scenario: Foreign-toplevel management is unavailable
- **WHEN** the compositor does not advertise foreign-toplevel management or tracker initialization fails
- **THEN** Alice SHALL continue operating without foreign-toplevel activation

### Requirement: Notification origin matching
Alice SHALL resolve a notification origin to a live foreign toplevel using normalized exact matching between the notification desktop-entry identity and foreign-toplevel app ID.

#### Scenario: Exactly one toplevel matches
- **WHEN** a notification has a desktop-entry identity and exactly one live toplevel has the same normalized app ID
- **THEN** Alice SHALL select that toplevel as the activation target

#### Scenario: One of multiple matching toplevels is active
- **WHEN** multiple live toplevels match the notification identity and exactly one is reported activated
- **THEN** Alice SHALL select the activated toplevel

#### Scenario: A unique most-recent matching toplevel exists
- **WHEN** multiple live toplevels match, none is uniquely active, and one has a unique most-recent activation observed by Alice
- **THEN** Alice SHALL select that most-recently activated toplevel

#### Scenario: Notification identity is unavailable or unmatched
- **WHEN** the notification has no desktop-entry identity or no live toplevel has a matching normalized app ID
- **THEN** Alice SHALL report no activation target

#### Scenario: Multiple candidates remain ambiguous
- **WHEN** multiple live toplevels match and activation history does not identify one unique candidate
- **THEN** Alice SHALL report no activation target rather than selecting by title or arbitrary ordering

### Requirement: Best-effort foreign toplevel activation
Alice SHALL request activation of a uniquely resolved notification toplevel on an available compositor seat, while treating compositor activation as advisory.

#### Scenario: A unique target and seat are available
- **WHEN** activation is requested for a notification identity that resolves to one live toplevel and an activation seat is available
- **THEN** Alice SHALL send a foreign-toplevel activation request for that handle and seat

#### Scenario: Activation cannot be requested
- **WHEN** no unique target, no usable seat, no protocol support, a closed handle, or a Wayland error prevents the request
- **THEN** Alice SHALL fail without disrupting Alice's notification server or snapshot runtime

#### Scenario: Compositor does not activate the target
- **WHEN** Alice sends an activation request and the compositor declines or does not honor it
- **THEN** Alice SHALL treat the outcome as a best-effort activation failure
