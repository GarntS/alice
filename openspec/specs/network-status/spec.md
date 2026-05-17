# Network Status Specification

## Purpose
Define implemented network interface detection, labeling, refresh, and bar display behavior.

## Requirements

### Requirement: Interface scanning
Alice SHALL determine network status by scanning `/sys/class/net` and ignoring the loopback interface.

#### Scenario: Interfaces are scanned
- **WHEN** Alice reads network state
- **THEN** Alice SHALL ignore `lo`
- **AND** Alice SHALL treat interfaces with `operstate` of `up` or `unknown` as connected

### Requirement: Wi-Fi preference and labeling
Alice SHALL prefer connected wireless interfaces over wired interfaces.

#### Scenario: Connected Wi-Fi exists
- **WHEN** a connected interface contains a `wireless` marker
- **THEN** Alice SHALL report network kind `Wifi`
- **AND** Alice SHALL attempt to read the SSID using `iw dev <interface> link`
- **AND** Alice SHALL fall back to the interface name when no SSID is available

### Requirement: Wired and disconnected states
Alice SHALL report wired connectivity when no connected Wi-Fi is found and at least one non-wireless interface is connected, otherwise disconnected.

#### Scenario: Wired interface is connected
- **WHEN** no connected wireless interface exists and a connected wired interface exists
- **THEN** Alice SHALL report network kind `Wired` with label `Connected`

#### Scenario: No connected interfaces exist
- **WHEN** no non-loopback interface is connected
- **THEN** Alice SHALL report network kind `Disconnected` with label `Disconnected`

### Requirement: Network refresh
Alice SHALL trigger snapshot rebuilds on network interface directory changes.

#### Scenario: `/sys/class/net` changes
- **WHEN** the notify watcher observes a non-recursive event in `/sys/class/net`
- **THEN** Alice SHALL trigger a snapshot rebuild

### Requirement: Configurable label visibility
Alice SHALL allow the network label to be hidden while retaining the network icon.

#### Scenario: Network label config is false
- **WHEN** `network.show_label` is false
- **THEN** the top bar network module SHALL render an empty label next to the network icon
