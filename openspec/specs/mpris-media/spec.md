# MPRIS Media Specification

## Purpose
Define implemented MPRIS media discovery, bar display, media panel, and media control actions.

## Requirements

### Requirement: MPRIS player discovery
Alice SHALL discover MPRIS players from the D-Bus session bus by listing names with the `org.mpris.MediaPlayer2.` prefix.

#### Scenario: Players are present
- **WHEN** Alice reads media state
- **THEN** Alice SHALL inspect discovered MPRIS players at `/org/mpris/MediaPlayer2`
- **AND** Alice SHALL prefer the first currently playing player
- **AND** Alice SHALL fall back to the first non-playing player with usable metadata

### Requirement: Media snapshot fields
Alice SHALL expose current media metadata and playback position in `MediaSnapshot` when a player has a non-empty title.

#### Scenario: Player metadata is readable
- **WHEN** a selected player exposes metadata
- **THEN** Alice SHALL populate title, artist, album title, art URL, formatted position and length labels, raw microsecond positions, and playing state

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
