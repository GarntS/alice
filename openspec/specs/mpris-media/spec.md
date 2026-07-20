# MPRIS Media Specification

## Purpose
Define implemented MPRIS media discovery, bar display, media panel, and media control actions.

## Requirements

### Requirement: MPRIS player discovery
Alice SHALL discover MPRIS players from the D-Bus session bus by listing names with the `org.mpris.MediaPlayer2.` prefix during MPRIS cache startup, and SHALL keep discovered players current by watching D-Bus owner changes for that prefix.

#### Scenario: Players are present at startup
- **WHEN** the MPRIS runtime service starts
- **THEN** Alice SHALL inspect discovered MPRIS players at `/org/mpris/MediaPlayer2`
- **AND** Alice SHALL cache players with usable metadata
- **AND** Alice SHALL prefer the first currently playing player
- **AND** Alice SHALL fall back to the first non-playing player with usable metadata

#### Scenario: Player appears after startup
- **WHEN** a D-Bus name with the `org.mpris.MediaPlayer2.` prefix gains an owner
- **THEN** Alice SHALL inspect that player at `/org/mpris/MediaPlayer2`
- **AND** Alice SHALL update the cached media state
- **AND** Alice SHALL trigger a snapshot rebuild

#### Scenario: Player disappears after startup
- **WHEN** a cached MPRIS player loses its D-Bus owner
- **THEN** Alice SHALL remove that player from the cached media state
- **AND** Alice SHALL trigger a snapshot rebuild

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

### Requirement: MPRIS property change subscription
Alice SHALL subscribe to relevant MPRIS player property changes and update cached media state when those changes occur.

#### Scenario: Player properties change
- **WHEN** a cached MPRIS player emits `PropertiesChanged` for `org.mpris.MediaPlayer2.Player` at `/org/mpris/MediaPlayer2`
- **THEN** Alice SHALL update cached fields for relevant changes such as `Metadata`, `PlaybackStatus`, or `Position`
- **AND** Alice SHALL trigger a snapshot rebuild when the projected media snapshot changes

### Requirement: Derived playback position
Alice SHALL derive the displayed playback position from the cached base position and monotonic elapsed time while the selected player is playing.

#### Scenario: Selected player is playing
- **WHEN** Alice projects cached media state into a `MediaSnapshot`
- **AND** the selected player is playing
- **THEN** Alice SHALL add elapsed monotonic time since the cached base position was observed to the projected position
- **AND** Alice SHALL format the position label from the projected position

#### Scenario: Selected player is paused or stopped
- **WHEN** Alice projects cached media state into a `MediaSnapshot`
- **AND** the selected player is not playing
- **THEN** Alice SHALL use the cached base position without adding elapsed time

### Requirement: Media control target consistency
Alice SHALL prefer controlling the cached selected MPRIS player when handling media controls, while preserving fallback behavior if that target is unavailable.

#### Scenario: Cached player is available
- **WHEN** Flutter requests `previous`, `playPause`, `next`, or an absolute seek
- **AND** the cached selected player is still available on D-Bus
- **THEN** Rust SHALL send the requested MPRIS method to that player

#### Scenario: Cached player is unavailable
- **WHEN** Flutter requests a media control action
- **AND** the cached selected player cannot be used
- **THEN** Rust SHALL fall back to discovering an available MPRIS control target using the existing player-selection behavior

### Requirement: Top-bar media module
Alice SHALL render the media top-bar module only when a media snapshot is present.

#### Scenario: Media is available
- **WHEN** the media snapshot exists
- **THEN** the bar SHALL show a pill with play/pause icon and `Title - Artist - position/length`
- **AND** clicking the pill SHALL toggle the media panel

### Requirement: Media panel display
Alice SHALL render album art, metadata, scrubber, and playback controls in the media panel.

#### Scenario: Media panel opens with active media
- **WHEN** the media panel renders a media snapshot
- **THEN** Alice SHALL display title, artist, optional album, optional album art, position/length labels, seek slider, previous, play/pause, and next controls

#### Scenario: No media is available
- **WHEN** the media panel renders with no media snapshot
- **THEN** Alice SHALL display a no-active-player message

### Requirement: Media actions
Alice SHALL send implemented MPRIS control methods through Rust FRB calls.

#### Scenario: Playback control is requested
- **WHEN** Flutter requests `previous`, `playPause`, or `next`
- **THEN** Rust SHALL call `Previous`, `PlayPause`, or `Next` on the selected MPRIS player

#### Scenario: Seek is requested
- **WHEN** Flutter requests an absolute seek position in microseconds
- **THEN** Rust SHALL call MPRIS `SetPosition` with the current track id or the no-track fallback path
