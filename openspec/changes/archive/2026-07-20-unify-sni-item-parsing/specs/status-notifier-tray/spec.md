## MODIFIED Requirements

### Requirement: Tray item registration
Alice SHALL accept tray item and host registration calls, emit registration signals when registration state changes, and trigger snapshot refreshes when registration state changes. Registration input and watcher-property input SHALL share one semantic parser for StatusNotifier item service names and object paths, and canonical watcher IDs SHALL be derived from that parsed value.

#### Scenario: Tray item registers by service name
- **WHEN** a StatusNotifierItem registers with a non-empty service name and no object path
- **THEN** Alice SHALL parse that service name with the shared identifier parser
- **AND** Alice SHALL use `/StatusNotifierItem` as its object path
- **AND** Alice SHALL emit the same canonical registered item id as before this refactor

#### Scenario: Tray item registers by object path
- **WHEN** a StatusNotifierItem registers with an object path and the D-Bus sender is available
- **THEN** Alice SHALL parse the sender as the service name and the supplied path as the object path
- **AND** Alice SHALL derive the canonical registered item id from those parsed fields

#### Scenario: Watcher registration property is read
- **WHEN** Alice reads a service-only or service-plus-path identifier from `RegisteredStatusNotifierItems`
- **THEN** Alice SHALL use the same parser used by registration
- **AND** the resulting service name and object path SHALL match registration canonicalization

#### Scenario: Tray item registers
- **WHEN** a parsed canonical item id is newly added
- **THEN** Alice SHALL add it to watcher state
- **AND** Alice SHALL emit `StatusNotifierItemRegistered` with that id
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Tray host registers
- **WHEN** a StatusNotifierHost registers and Alice does not already have a registered host
- **THEN** Alice SHALL mark a host as registered
- **AND** Alice SHALL emit `StatusNotifierHostRegistered`
- **AND** Alice SHALL trigger a snapshot rebuild
