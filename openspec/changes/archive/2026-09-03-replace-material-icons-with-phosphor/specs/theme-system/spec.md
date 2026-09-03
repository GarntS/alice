## ADDED Requirements

### Requirement: Non-accent duotone secondary colors
Alice SHALL define fixed gray colors for the secondary layer of duotone icons when accent-colored icon layers are disabled.

#### Scenario: Light theme uses a gray secondary layer
- **WHEN** Alice renders a duotone icon in the light theme with `theme.use_accent_on_icons` set to `false`
- **THEN** the icon's secondary layer SHALL use Alice's fixed dark gray token

#### Scenario: Dark theme uses a gray secondary layer
- **WHEN** Alice renders a duotone icon in the dark theme with `theme.use_accent_on_icons` set to `false`
- **THEN** the icon's secondary layer SHALL use Alice's fixed light gray token
