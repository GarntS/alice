# Network Panel Specification

## Purpose

Define the interactive Network panel that presents local adapter and WireGuard tunnel state without claiming unavailable peer health.

## Requirements

### Requirement: Network panel interaction
Alice SHALL open and close a Network panel when the user activates the network control in the top bar, using the same single-open-panel behavior as other Alice panels.

#### Scenario: Network control is activated
- **WHEN** the user activates the network control
- **THEN** Alice SHALL open the Network panel anchored to that control
- **AND** Alice SHALL visually indicate that the control's panel is open

#### Scenario: Network control is activated while its panel is open
- **WHEN** the user activates the network control while the Network panel is open for that bar
- **THEN** Alice SHALL close the Network panel

### Requirement: Hardware adapter cards
Alice SHALL render one adapter card for each non-loopback, hardware-backed Wi-Fi or Ethernet adapter and SHALL exclude WireGuard interfaces from this section.

#### Scenario: Hardware adapters are present
- **WHEN** one or more eligible adapters are present
- **THEN** Alice SHALL render one card per adapter
- **AND** each card SHALL show the adapter name, link state, and preferred local IP address or an explicit no-address state

#### Scenario: Wi-Fi adapter card is rendered
- **WHEN** an eligible adapter is identified as Wi-Fi
- **THEN** its card SHALL show the associated network name when available
- **AND** it SHALL omit the SSID row when there is no associated, non-empty network name
- **AND** it SHALL expose unavailable or not-associated details in the Wi-Fi icon tooltip rather than as a network-name placeholder

#### Scenario: Virtual adapter is present
- **WHEN** a non-loopback interface is not hardware-backed and is not WireGuard
- **THEN** Alice SHALL NOT render it among the hardware adapter cards

### Requirement: Preferred address display
Alice SHALL display an adapter's assigned IPv4 address when one exists, otherwise its assigned IPv6 address when one exists, and otherwise no address.

#### Scenario: Adapter has IPv4 and IPv6 addresses
- **WHEN** an adapter has at least one assigned IPv4 address and one assigned IPv6 address
- **THEN** Alice SHALL display an IPv4 address

#### Scenario: Adapter has only IPv6 address
- **WHEN** an adapter has no assigned IPv4 address and has an assigned IPv6 address
- **THEN** Alice SHALL display an IPv6 address

#### Scenario: Adapter has no assigned address
- **WHEN** an adapter has neither an assigned IPv4 nor an assigned IPv6 address
- **THEN** Alice SHALL show that no address is assigned

### Requirement: Unprivileged WireGuard cards
Alice SHALL render one card for each detected WireGuard interface and SHALL limit its content to unprivileged, generic interface data. When no WireGuard interfaces are detected, Alice SHALL omit all WireGuard content, including empty-state messages.

#### Scenario: WireGuard interface is detected
- **WHEN** a WireGuard interface is present
- **THEN** Alice SHALL render a card showing its name, administrative and operational link state, preferred host IP address, and generic received/transmitted traffic counters

#### Scenario: Peer information would require privilege
- **WHEN** WireGuard peer addresses, peer endpoints, handshakes, keys, listening ports, or per-peer counters are not accessible without `CAP_NET_ADMIN`
- **THEN** Alice SHALL NOT display those fields
- **AND** Alice SHALL NOT classify peer health or tunnel reachability from generic interface state or counters

### Requirement: Consistent panel and card presentation
Alice SHALL use the shared panel title styling with the title `Networks`, SHALL omit `Adapters` and `WireGuard` subheadings, and SHALL distinguish cards with icons and typography.

#### Scenario: Network cards are rendered
- **WHEN** Alice renders the panel
- **THEN** the panel title SHALL read `Networks` using the standard panel shell
- **AND** each wireless adapter card SHALL show a Wi-Fi icon, each other adapter card SHALL show a network icon, and each WireGuard card SHALL show a keyhole icon
- **AND** adapter names SHALL have greater visual emphasis than status text, with addresses and network names emphasized
- **AND** the panel SHALL NOT display `Adapters` or `WireGuard` subheadings

#### Scenario: Compact card rows are rendered
- **WHEN** Alice renders an interface card
- **THEN** its first row SHALL show the interface icon, interface name, separator, and administrative status
- **AND** a Wi-Fi card's middle row SHALL show only an associated, non-empty SSID without a `Wi-Fi` prefix, and SHALL otherwise be omitted
- **AND** a WireGuard card's middle row SHALL show generic RX/TX counters
- **AND** other adapters SHALL omit the middle row
- **AND** the final row SHALL show a `link` icon, operational link state, an `at` icon, and the preferred host address or no-address state
- **AND** long values SHALL be constrained to one visual line with the full value available through a tooltip

#### Scenario: No WireGuard interfaces are present
- **WHEN** Alice has no detected WireGuard interfaces
- **THEN** the panel SHALL NOT render WireGuard cards, headings, or placeholder content

### Requirement: SSID byte-safe presentation
Alice SHALL preserve a Wi-Fi network name's valid UTF-8 text and SHALL visibly escape non-UTF-8 bytes rather than replacing or discarding them.

#### Scenario: SSID contains non-UTF-8 bytes
- **WHEN** an associated Wi-Fi network name contains bytes that are not valid UTF-8
- **THEN** Alice SHALL render each non-UTF-8 byte as a hexadecimal `\xNN` escape
