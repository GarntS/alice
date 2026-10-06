## Purpose

Provide configurable audible cues for newly received Alice notifications without compromising notification delivery or repeating sounds for notification updates.

## Requirements

### Requirement: Sound configuration and defaults
Alice SHALL accept `notifications.sound.enable`, optional `notifications.sound.file`, and `notifications.sound.volume` in `config.yaml`. Omitted values SHALL default to enabled, the bundled sound, and 50 percent volume. Volume SHALL be an integer from 0 through 100 inclusive. A supplied file SHALL be a nonempty absolute local file path; relative paths, URLs, and shell-style home-directory expansion SHALL NOT be accepted as custom sound paths. Invalid sound settings SHALL be diagnosed and SHALL NOT prevent notification delivery.

#### Scenario: Existing configuration omits sound settings
- **WHEN** the configuration omits the sound section or its optional fields
- **THEN** Alice SHALL use the corresponding defaults: enabled, bundled sound, and volume 50

#### Scenario: Custom sound configured
- **WHEN** a user specifies an absolute file path and volume 75
- **THEN** Alice SHALL use that file at 75 percent playback volume

#### Scenario: Invalid sound settings
- **WHEN** a supplied file path is relative or empty, or volume is outside 0 through 100
- **THEN** Alice SHALL diagnose the invalid sound settings and disable sound for that configuration without preventing notification delivery

### Requirement: Bundled notification sound
Alice SHALL ship a short, gentle chime usable as the default notification sound without requiring a user-provided file or access to the source checkout.

#### Scenario: Installed application uses default sound
- **WHEN** installed Alice receives an eligible notification and no custom file is specified
- **THEN** Alice SHALL play its bundled chime at the configured volume

### Requirement: Receipt-based playback policy
Alice SHALL request sound playback once for each newly admitted external or internally generated notification when sound is enabled and volume is nonzero. Alice SHALL NOT sound replacements of retained notifications, changes in read state, dismissal, panel opening, popup visibility changes, or snapshot refreshes. Sound SHALL be independent of the popup enable setting. An external notification with a true freedesktop `suppress-sound` hint SHALL remain silent. Sender-provided sound names or files SHALL NOT override Alice's configured sound.

#### Scenario: New notification without popups
- **WHEN** a new external notification is admitted with popups disabled and sound enabled at nonzero volume
- **THEN** Alice SHALL request playback once using its configured sound

#### Scenario: Internal calendar notification
- **WHEN** a new internal calendar reminder is admitted with sound enabled at nonzero volume
- **THEN** Alice SHALL request playback once using the same sound policy as external notifications

#### Scenario: Replacement remains silent
- **WHEN** an external notification replaces an existing retained notification
- **THEN** Alice SHALL update the notification without requesting sound playback

#### Scenario: Replacement target no longer exists
- **WHEN** an external notification specifies a replacement ID that is not retained and is admitted as a new notification
- **THEN** Alice SHALL treat it as a new notification for sound eligibility

#### Scenario: Sender requests silence
- **WHEN** an external notification includes a true `suppress-sound` hint
- **THEN** Alice SHALL deliver the notification without sound

#### Scenario: Sound disabled or muted
- **WHEN** sound is disabled or volume is zero
- **THEN** Alice SHALL deliver notifications without playback

#### Scenario: UI or snapshot activity
- **WHEN** Alice refreshes snapshots, opens a notification panel, changes popup visibility, marks a notification read, or dismisses it
- **THEN** Alice SHALL NOT request sound playback as a result of that activity

### Requirement: Playback failure isolation
Audio initialization, file access, decoding, and playback failures SHALL NOT prevent or delay notification delivery while waiting for playback completion. Alice SHALL log sound failures without generating additional notifications. A failed custom sound SHALL NOT fall back to the bundled sound.

#### Scenario: Custom file cannot be played
- **WHEN** the configured custom file is missing, unreadable, or unsupported
- **THEN** Alice SHALL log the failure and keep the notification silent without falling back to the bundled sound
- **AND** notification storage and UI delivery SHALL continue normally

#### Scenario: Audio output unavailable
- **WHEN** audio output initialization or playback fails
- **THEN** Alice SHALL log the failure and continue delivering notifications normally
