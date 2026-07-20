## MODIFIED Requirements

### Requirement: Media snapshot fields
Alice SHALL expose current media metadata and playback position in `MediaSnapshot` when a player has a non-empty title, using the single cache-backed MPRIS provider path for normal snapshot assembly. Fresh blocking D-Bus discovery SHALL remain available only where required for media-control fallback and SHALL NOT exist as an alternate normal snapshot provider.

#### Scenario: Player metadata is readable
- **WHEN** a selected player exposes metadata
- **THEN** Alice SHALL populate title, artist, album title, art URL, formatted position and length labels, raw microsecond positions, and playing state

#### Scenario: Snapshot assembly reads media
- **WHEN** Alice builds a bar snapshot
- **THEN** Alice SHALL read media from the cached MPRIS state
- **AND** Alice SHALL NOT rediscover all MPRIS players as part of normal snapshot assembly
- **AND** the native implementation SHALL NOT retain an unused blocking MPRIS snapshot provider parallel to the cache-backed provider

#### Scenario: Control fallback needs fresh discovery
- **WHEN** the cached selected player cannot be used for a media control
- **THEN** Alice SHALL retain the existing fresh D-Bus discovery path for choosing a control target
