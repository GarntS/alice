## RENAMED Requirements

- FROM: `### Requirement: Interface scanning`
- TO: `### Requirement: Interface and address scanning`
- FROM: `### Requirement: Wi-Fi preference and labeling`
- TO: `### Requirement: Wi-Fi association and network name`
- FROM: `### Requirement: Wired and disconnected states`
- TO: `### Requirement: Bar icon precedence`

## MODIFIED Requirements

### Requirement: Interface and address scanning
Alice SHALL determine network status from Linux route-link and route-address state, ignoring the loopback interface. Alice SHALL retain interface presence, administrative state, operational state, assigned addresses, and generic traffic activity as distinct observations.

#### Scenario: Interfaces are scanned
- **WHEN** Alice reads network state
- **THEN** Alice SHALL ignore `lo`
- **AND** Alice SHALL collect each non-loopback interface's administrative state, operational state, kind, generic traffic counters, and assigned addresses when available

#### Scenario: Operational state is unknown
- **WHEN** an interface reports operational state `unknown`
- **THEN** Alice SHALL present that state as unknown
- **AND** Alice SHALL NOT treat it as proof of connectivity or failure

### Requirement: Wi-Fi association and network name
Alice SHALL identify Wi-Fi interfaces and obtain association state and network name without invoking a command or subprocess.

#### Scenario: Connected Wi-Fi exists
- **WHEN** a Wi-Fi interface has an associated network in the kernel's existing Wi-Fi information
- **THEN** Alice SHALL report that interface as associated
- **AND** Alice SHALL expose its SSID when present

#### Scenario: Wi-Fi information is unavailable
- **WHEN** Wi-Fi association or network-name information cannot be collected because the backend is unsupported, permission is denied, or data is absent
- **THEN** Alice SHALL distinguish that condition from an explicitly not-associated interface
- **AND** Alice SHALL NOT infer association from administrative state, operational state, or address assignment alone

### Requirement: Bar icon precedence
Alice SHALL render the network control as an icon without a text label and SHALL select its icon from observed Wi-Fi association and usable local addressing.

#### Scenario: Associated Wi-Fi has an address
- **WHEN** a Wi-Fi adapter is associated with a Wi-Fi network, has administrative state up, and has an assigned IPv4 or IPv6 address
- **THEN** Alice SHALL show the `wifi-high` icon

#### Scenario: Wired interface is connected
- **WHEN** no associated Wi-Fi adapter with an assigned address exists
- **AND** any non-loopback network interface has administrative state up and an assigned IPv4 or IPv6 address
- **THEN** Alice SHALL show the `network` icon

#### Scenario: Wi-Fi hardware exists without usable networking
- **WHEN** no associated Wi-Fi adapter with an assigned address exists
- **AND** no other non-loopback interface has administrative state up and an assigned IPv4 or IPv6 address
- **AND** a Wi-Fi adapter exists
- **THEN** Alice SHALL show the `wifi-x` icon

#### Scenario: No connected interfaces exist
- **WHEN** no associated Wi-Fi adapter with an assigned address exists
- **AND** no non-loopback interface has administrative state up and an assigned IPv4 or IPv6 address
- **AND** no Wi-Fi adapter exists
- **THEN** Alice SHALL show the `network-x` icon

### Requirement: Network refresh
Alice SHALL refresh network state when route-link or route-address changes occur and SHALL refresh generic traffic counters periodically.

#### Scenario: `/sys/class/net` changes
- **WHEN** Linux reports a non-loopback interface link change
- **THEN** Alice SHALL rebuild the network portion of the snapshot

#### Scenario: Link or address changes
- **WHEN** Linux reports a non-loopback interface link or IPv4/IPv6 address change
- **THEN** Alice SHALL rebuild the network portion of the snapshot

#### Scenario: Traffic counters change
- **WHEN** the periodic network counter refresh observes changed generic traffic counters
- **THEN** Alice SHALL update the network snapshot

## REMOVED Requirements

### Requirement: Configurable label visibility
**Reason**: The network control is always icon-only and no longer supports a label.

**Migration**: Remove `network.show_label` from Alice configuration; it has no replacement.
