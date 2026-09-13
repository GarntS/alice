# Bluetooth Device Management Specification

## Purpose
Provide a BlueZ-backed Bluetooth panel that lets users discover, pair, trust, connect, and disconnect nearby and remembered devices without an external network manager.
## Requirements
### Requirement: Conditional Bluetooth availability
Alice SHALL expose Bluetooth controls only when the BlueZ service is available and at least one local Bluetooth adapter is powered. Alice SHALL remove Bluetooth controls and close its panel when either condition ceases to be true.

#### Scenario: BlueZ and a powered adapter are available
- **WHEN** BlueZ is running and at least one local adapter is powered
- **THEN** Alice SHALL display a Bluetooth top-bar control that opens the Bluetooth panel

#### Scenario: Bluetooth becomes unavailable
- **WHEN** BlueZ stops or no local adapter remains powered while the Bluetooth panel is open
- **THEN** Alice SHALL remove the top-bar Bluetooth control
- **AND** Alice SHALL close the Bluetooth panel

### Requirement: Aggregated Bluetooth device presentation
Alice SHALL aggregate observations from all powered local adapters and display each device at most once. Alice SHALL label a device by its user-friendly alias when non-empty, otherwise its advertised name when non-empty, otherwise its Bluetooth address. Alice SHALL select a device-class or LE-appearance icon when recognized and a generic Bluetooth icon otherwise.

#### Scenario: Device has overlapping observations
- **WHEN** the same device is observed by more than one powered adapter or belongs to multiple panel states
- **THEN** Alice SHALL render one device row identified by its Bluetooth address
- **AND** Alice SHALL place it only in the highest applicable state in this order: connected, known, nearby

#### Scenario: Device has no usable name or recognized class
- **WHEN** a displayed device has neither a non-empty alias nor a non-empty advertised name, or has no recognized class or appearance
- **THEN** Alice SHALL display its Bluetooth address as its label
- **AND** Alice SHALL display the generic Bluetooth icon when no class or appearance icon applies

### Requirement: Connected and known device lists
Alice SHALL display connected devices and paired, disconnected devices in distinct lists. The known-device list SHALL contain paired devices only.

#### Scenario: Connected device is present
- **WHEN** an aggregated Bluetooth device is connected
- **THEN** Alice SHALL display it in the Connected list
- **AND** Alice SHALL offer a Disconnect action

#### Scenario: Paired device is disconnected
- **WHEN** an aggregated Bluetooth device is paired and not connected
- **THEN** Alice SHALL display it in the Known devices list
- **AND** Alice SHALL offer a Connect action

### Requirement: Timed nearby-device discovery
Alice SHALL provide a Scan action that starts discovery on every powered adapter concurrently for 15 seconds. It SHALL present merged nearby results after and during discovery, retaining them until the next scan begins.

#### Scenario: User starts a scan
- **WHEN** the user activates Scan while one or more adapters are powered
- **THEN** Alice SHALL start discovery on every powered adapter for 15 seconds
- **AND** Alice SHALL show that scanning is in progress
- **AND** Alice SHALL clear the previous nearby-device results before collecting the new results

#### Scenario: Scan completes
- **WHEN** the 15-second discovery interval ends
- **THEN** Alice SHALL stop discovery started by that scan
- **AND** Alice SHALL retain the merged nearby-device results until a subsequent scan begins

### Requirement: Nearby device connection
Alice SHALL offer Connect for an unconnected nearby device. For an unpaired device, Connect SHALL pair the device, mark it trusted after successful pairing, then connect it.

#### Scenario: User connects a paired nearby device
- **WHEN** the user selects Connect for a paired, unconnected nearby device
- **THEN** Alice SHALL connect the device

#### Scenario: User connects an unpaired nearby device
- **WHEN** the user selects Connect for an unpaired nearby device
- **THEN** Alice SHALL pair the device
- **AND** Alice SHALL mark it trusted after pairing succeeds
- **AND** Alice SHALL connect it after it is trusted

### Requirement: Pairing and authorization interaction
Alice SHALL act as BlueZ's default pairing agent while Bluetooth controls are available. Alice SHALL present PIN/passkey entry, passkey display, numeric confirmation, and device or service authorization requests, with explicit user approval where authorization is requested.

#### Scenario: BlueZ requests pairing input or confirmation
- **WHEN** BlueZ requests a PIN, passkey, or numeric confirmation for a user-initiated pairing operation
- **THEN** Alice SHALL display the requested value or input control in the Bluetooth panel
- **AND** Alice SHALL submit the user response or cancellation to BlueZ

#### Scenario: BlueZ requests authorization
- **WHEN** BlueZ requests authorization for a device or service during a user-initiated operation
- **THEN** Alice SHALL display an allow or deny prompt identifying the device and service when available
- **AND** Alice SHALL forward the user's decision to BlueZ

#### Scenario: Alice cannot become the default agent
- **WHEN** BlueZ rejects Alice's request to become the default pairing agent
- **THEN** Alice SHALL report the failure for the attempted pairing
- **AND** Alice SHALL NOT claim that pairing is in progress

### Requirement: Per-device operation feedback
Alice SHALL show operation progress and retryable failures per device for pairing, connecting, and disconnecting operations.

#### Scenario: Device operation is active
- **WHEN** Alice is pairing, connecting, or disconnecting a device
- **THEN** Alice SHALL disable conflicting actions for that device
- **AND** Alice SHALL display its active operation state

#### Scenario: Device operation fails
- **WHEN** pairing, trusting, connecting, or disconnecting a device fails
- **THEN** Alice SHALL display an error on that device's row
- **AND** Alice SHALL leave an applicable action available for retry
